package Asteryst::AGI;

# ABSTRACT: Asteryst voice application framework

use Data::Dump 'pp';
use Data::Dumper;
use Devel::StackTrace;
use Exception::Class;
use Carp qw/croak/;
use Profile::Log;
use DBIx::Class::Storage::DBI::Replicated;

use Asteryst::Config;
use Asteryst::ContentFetcher;
use Asteryst::AGI::Session;

use Moose;
    extends 'Asterisk::FastAGI';

# make sure controllers are loaded and compile ok
use Asteryst::AGI::Controller::Ad;
use Asteryst::AGI::Controller::Prompt;
use Asteryst::AGI::Controller::UserInput;
use Class::Load;

has 'session' => (
    is => 'rw',
    isa => 'Maybe[Asteryst::AGI::Session]',
    handles => [qw/context/],
);

has 'caller' => (
    is => 'rw',
    isa => 'Maybe[Asteryst::Schema::AsterystDB::Result::Caller]',
    handles => {
        caller_id => 'phonenumber',
    },
    clearer => 'clear_caller',
);

# are we done dispatching?
has 'detached' => (
    is => 'rw',
    default => 0,
);

# are we done dispatching?
has 'no_detach_on_hangup' => (
    is => 'rw',
    isa => 'Bool',
    default => 0,
);

# last fatal error we died from
has 'fatal_error' => (
    is => 'rw',
    default => 0,
);

# per-request stash
has 'stash' => (
    is => 'rw',
    isa => 'HashRef',
);

# schema object
has 'schema' => (
    is => 'rw',
);

# cache dbh for a request
has '_dbh' => (
    is => 'rw',
    clearer => 'clear_cached_dbh',
);

has 'speech_engine_loaded' => (
    is => 'rw',
);

has 'loaded_controllers' => (
    is => 'rw',
    isa => 'HashRef',
);

has 'hungup' => (
    is => 'rw',
    isa => 'Bool',
);

# stack of currently loaded grammars
has 'loaded_grammars' => (   
    is => 'rw',
    isa => 'ArrayRef',
    default => sub { [] },
    lazy => 1,
);

has '_profiler' => (
    is => 'rw',
    isa => 'Profile::Log',
    builder => 'build_profiler',
    lazy => 1,
);

has 'content_fetcher' => (
    is => 'rw',
    isa => 'Asteryst::ContentFetcher',
    builder => 'build_content_fetcher',
    lazy => 1,
);

has 'content_saver' => (
    is => 'rw',
    isa => 'Asteryst::ContentSaver',
    builder => 'build_content_saver',
    lazy => 1,
);

has 'speech_enabled' => (
    is => 'rw',
    isa => 'Bool',
);


use FindBin;

# load controllers
use Class::Autouse;
Class::Autouse->load_recursive("Asteryst::AGI::Controller");

use Asteryst::AGI::Events;

# default Net::Server config options
sub default_values {
    return {
        log_level => 3,
        log_file  => '/var/asteryst/',
    };
}

# returns if loading grammar was successful
sub push_grammar {
    my ($self, $grammar) = @_;
    
    return unless $self->speech_enabled;
    
    push @{$self->loaded_grammars}, $grammar;
    return $self->activate_grammar($grammar);
}

# returns grammar popped off the stack
sub pop_grammar {
    my ($self) = @_;
    
    return unless $self->speech_enabled;
    
    my $grammar = pop @{$self->loaded_grammars};
    return undef unless $grammar;
    
    $self->deactivate_grammar($grammar);
    return $grammar;
}

sub activate_grammar {
    my ($self, $grammar_name) = @_;

    return unless $self->speech_enabled;

    croak "No grammar specified to activate" unless $grammar_name;

    my $res = $self->agi->exec('SpeechActivateGrammar', $grammar_name);
    if (defined $res && $res == 0) {
        $self->debug("GRAMMAR Activated grammar $grammar_name");
        return 1;
    } else {
        $res = 'undef' unless defined $res;
        $self->fatal_error("GRAMMAR Failed to activate grammar $grammar_name, res=$res");
        return 0;
    }
}

sub deactivate_grammar {
    my ($self, $grammar_name) = @_;
    
    return unless $self->speech_enabled;

    croak "No grammar specified to deactivate" unless $grammar_name;

    my $res = $self->agi->exec('SpeechDeactivateGrammar', $grammar_name);
    if (defined $res && $res == 0) {
        $self->debug("GRAMMAR Deactivated grammar $grammar_name");
        return 1;
    } else {
        $res = 'undef' unless defined $res;
        $self->debug("GRAMMAR Failed to deactivate grammar $grammar_name, res=$res");
        return 0;
    }
}

=head2 config

Return the config, read in from asteryst.yml (other formats are supported as well).

=cut
my $config = Asteryst::Config->get;
sub config {
    return $config;
}

sub configure_hook {
    my ($self) = @_;

    # Preload config file, so that any errors (e.g. absence of the file) are evident up-front.
    $self->config or die "No config loaded";
    
    $self->check_config or die;
    
    $self->speech_enabled($self->config->{agi}{speech_enabled} ? 1 : 0);
}

sub noop {
    my ($self) = @_;

    die q[found an attempt to call noop.  noop doesn't work, due to Asterisk::AGI problems, so we've disabled it];
}

sub check_config {
    my ($self) = @_;

    my @required_agi = qw/ sound_file_extension log_file /;
    foreach my $required (@required_agi) {
        die "agi/$required missing" unless $self->config->{agi}{$required};
    }
    
    return 1;
}

sub init_speech_engine {
    my ($self) = @_;
    
    return unless $self->speech_enabled;

    # allow only one keypress to interrupt speech. this may need adjustment.
    $self->agi->set_variable(SPEECH_DTMF_MAXLEN => 1);

    # load speech engine
    my $res = $self->agi->exec('SpeechCreate');
    $res = 'undef' unless defined $res;
    
    my $engine_loaded = $self->var('SPEECH(status)');
    
    if ($engine_loaded) {
        $self->debug("Loaded speech engine, SPEECH(status)=$engine_loaded");
        my $busy_file = Asteryst::AGI::Controller::Prompt->get_path($self, 'busy');
        $self->agi->exec('SpeechProcessingSound', $busy_file);
        $self->speech_engine_loaded(1);
        
        return 1;
    } else {
        $self->fatal_detach("Could not load speech engine");
        $self->speech_engine_loaded(0);
        
        return 0;
    }
}

# initialize application, before accepting requests
sub setup {
    my ($self) = @_;
    
    # preload some controllers
    my $preload_controllers = $self->config->{agi}{preload_controllers} || [];
    foreach my $preload (@$preload_controllers) {
        my $package = join('::', __PACKAGE__, 'Controller', $preload);
        Class::Load::load_class($package);
        $self->forward("/$preload/LOAD_CONTROLLER");
    }
}

# reset state between requests
sub reset_request {
    my ($self) = @_;
    
    $self->init_speech_engine;

    $self->loaded_grammars([]);

    # reset state
    $self->clear_cached_dbh;
    $self->hungup(0);
    $self->detached(0);
    $self->fatal_error(0);
    $self->clear_caller;
    $self->stash({});
    $self->no_detach_on_hangup(0);
    
    $self->agi->set_autohangup($self->config->{agi}{max_call_time});
    
    my $hangup_cb = sub {
        my $code = shift;
        
        $self->log(4, "Got AGI callback with code=$code");

        if ($code == -1) {
            # got hangup notification
            $self->hungup(1);

            if ($self->no_detach_on_hangup) {
                $self->log(2, "Caller hung up, but no_detach_on_hangup is set");
            } else {
                $self->log(1, "Caller hung up, detaching");
                $self->detach;
            }
        }
    };
    
    $self->agi->setcallback($hangup_cb);
}

sub cleanup {
    my ($self) = @_;

    # clear request variables
    $self->stash({});

    if (0) {
        # destroy controllers
        my $loaded_controllers = $self->loaded_controllers || {};
        foreach my $controller (values %$loaded_controllers) {
            $self->debug("Destroying controller $controller") if 0;
            $controller->UNLOAD_CONTROLLER($self);
        }
    
        $self->loaded_controllers({});
        # FIXME: if we clear the loaded controllers, we need to
        # destroy the singletons as well. how?
    }
    
    # unload speech engine
    if ($self->speech_engine_loaded) {
        $self->agi->exec('SpeechDestroy');
        $self->debug("Destroyed speech engine");
    }
}

# get an asterisk variable
sub var {
    my ($self, $var_name) = @_;
    return $self->agi->get_full_variable('${' . $var_name . '}');
}

# check if the current channel is active (i.e. not hung up)
sub channel_is_active {
    my ($self) = @_;
    return ! $self->hungup;
}

sub dbh {
    my ($self) = @_;
    
    return $self->_dbh if $self->_dbh;
    $self->_dbh(Asteryst::Common::get_db_connection());
    return $self->_dbh;
}

# this is a good place to hook in tracking logic for your application
sub log_action {
    my ($self, $action_name, $fields) = @_;
}

sub dump {
    my ($self, $obj, $name) = @_;
    my $msg = Data::Dumper->Dump([$obj], [$name]);
    $self->debug($msg);
}

sub _print {
    my ($self, $string) = @_;
    $self->log(3, "$string");
    return;
}

sub debug {
    my ($self, @msg) = @_;
    
    my $i = 1;
    for my $element (@msg) {
        if (ref $element) {
            # Suppress for now--we don't want big data dumps.
            #$self->_print(pp($element));

            # This will result in refs being printed as HASH($mem_addr)
            # or the like
            $self->_print($element);
        }
        else {
            $self->_print($element);
        }
        # Print a space before the next word...
        $self->_print(q[ ])
            # ... unless we've reached the end of the array.
            unless $i == @msg;
        $i++;
    }

    return;
}

sub error {
    my ($self, @msg) = @_;
    
    my ($package, $filename, $line) = caller;
    $self->log(0, "ERROR ($package, $filename, $line): @msg");
    return;
}

sub detach {
    my ($self) = @_;
    $self->detached(1);
    return;
}

# print fatal error (should log in db or something too)
# don't do any more forwards, play oops sound, hang up
sub fatal_detach {
    my ($self, $err) = @_;
    
    Carp::cluck("Got fatal error");
    
    $self->no_detach_on_hangup(0);
    
    $self->forward('/Prompt/fatal_error');
    $self->error("[FATAL] $err");
    $self->detach();
    return 0;
}

sub prompt {
    my ($c, $prompt, $text) = @_;
    return $c->forward("/Prompt/play", $prompt, $text);
}

sub earcon {
    my ($c, $earcon) = @_;
    $c->forward("/Prompt/earcon", $earcon);
}

# earcon to indicate we are busy doing something
sub busy {
    my ($c, $earcon) = @_;
    $c->forward("/Prompt/play_busy");
}

sub background {
    my ($c, $prompt) = @_;
    $c->forward("/Prompt/background", $prompt);
}

sub build_content_fetcher {
    my ($self) = @_;
    
    # this needs to be in the AGI as well
    my $expire = $self->config->{agi}{content_cache_expires} || 3600 * 24;
    my $file_extension = $self->config->{agi}{sound_file_extension};
    my $cache_dir = $self->config->{agi}{content_cache_directory};
    
    return Asteryst::ContentFetcher->new(
        cache_dir => $cache_dir,
        expire => $expire,
        file_extension => $file_extension,
    );
}


sub fetch_content_cached {
    my ($self, $content) = @_;
    
    if ($self->config->{agi}{use_local_content}) {
        return Asteryst::Content::get_wrapped_slin_filename($content->id);
    }
    
    $self->busy;
    $self->log(3, "Fetching content " . $content->id);
    
    # call AGI
    $self->profile_mark;
    $self->agi->exec("AGI", "asteryst_fetch_content.pl," . $content->id);
    $self->profile_did("fetch_content_cached");
    my $success = $self->var('content_fetch_success');
    my $path = $self->var('content_fetch_path');
    
    if (! $success) {
        my $err = $self->var('content_fetch_error') || "unknown";
        $self->error("Failed to fetch content error: $err, content id=" . $content->id);
        return;
    } elsif (! $self->check_if_content_path_exists($path)) {
        $self->error("Fetched content but path $path doesn't exist, content id=" . $content->id);
        return;
    }
    
    return $path;
}

sub check_if_content_path_exists {
    my ($c, $path) = @_;

    return 1 unless $c->config->{agi}{'check_content_existance'};
    my $check_path = $path;

    # add extension if missing
    my $content_ext = $c->config->{agi}{sound_file_extension};
    $check_path .= '.' . $content_ext unless $check_path =~ /\.$content_ext$/i;

    return (-e $check_path && -s $check_path); # file must exist and have a non-zero size
}

sub prepare_request {
    my $self = shift;
    
    $self->reset_request;
    
    my $agi = $self->agi;

    my $dbconfig = $self->config->{'Model::AsterystDB'};
    $self->log(4, Dumper($dbconfig));
    my $connect_info = $dbconfig->{connect_info};
    if ($connect_info) {
        $self->log(4, "Found DB connection info in config");
        my ($dsn, $user, $pw) = @$connect_info;

        my $replicants = $dbconfig->{replicants};
        if ($replicants) {
            $self->log(4, "Found replicants configuration");

            my $schema = Asteryst::Schema::AsterystDB->clone;
            $self->schema($schema);

            $self->schema->storage_type( ['::DBI::Replicated', {balancer_type => '::Random'}] );
            $self->schema->connection($dsn, $user, $pw);

            foreach my $replicant (@$replicants) {
                $self->log(4, "Connecting replicant $replicant->[0]");
            }
            $self->schema->storage->connect_replicants(@$replicants);
        }
    } else {
        $self->log(2, "Failed to find DB connection info in config. No database schema will be available.");
    }

    my $info = $self->input;
    $self->log(4, "got AGI call with input: " . Dumper($self->input));
    my $caller_id_name = $self->input('calleridname') || '';
    my $caller_id_num  = $self->sanitize_phone($self->input('callerid')) || '';
    my $dest_num       = $self->input('dnid') || $self->input('extension') || '';
    my $session_id     = $self->input('uniqueid');

    # create a session for this call
    my $session = new Asteryst::AGI::Session(
        session_id     => $session_id,
        context        => 'begin',
        agi            => $self,
        dnid           => $dest_num,
        caller_id_num  => $caller_id_num,
        caller_id_name => $caller_id_name,
    );
    $self->session($session);

    unless ($caller_id_num) {
        # no callerID number
        $agi->exec('wait', '1');
        $self->forward('/Prompt/no_caller_id');
        $self->debug("Got call with no callerID... bailing");
        $agi->hangup();
        return 0;
    }
    	
    $self->log(1, "Got call from $caller_id_name <$caller_id_num> to DID $dest_num");
	
    my $caller = $self->look_up_caller($caller_id_num);
    $self->caller($caller);
    if ($caller) {
        $self->log(2, "Using caller record for $caller_id_num: id=" . $caller->id);    
        $caller->increment_visit_count;
    }
    
    return 1;
}

sub look_up_caller {
    my ($self, $num) = @_;

    return unless $self->schema;
    
	my $caller = $self->schema->resultset('Caller')->search({
	    -or => [
	        { phonenumber => $num },
	        { phone2      => $num },
	    ],
	})->single;
	
	if (! $caller) {
	    # virgin caller
	    $self->debug("Virgin caller, creating caller record for $num...");
	    $caller = $self->schema->resultset('Caller')->create({
	        phonenumber => $num,
	    });
	} else {
	    $self->debug("Existing caller record found...");
	}
	
	return $caller;
}

sub finalize_request {
    my ($self) = @_;

    $self->context('end');
    $self->cleanup;
    
    $self->session(undef);
    
    $self->debug("Finished call, hanging up");
    $self->agi->hangup;
}

# overridden from Asterisk::FastAGI
sub _parse_request {
  my $self = shift;

  # Grab the method and optional path.
  my $req = $self->{server}{input}{request};
  unless ($req) {
      $self->debug("Did not get request string from AGI server");
      return;
  }

  my ($class, $method, $param_string) = $self->_parse_request_uri($req);

  my %params;

  if (defined $param_string) {
      my (@pairs) = split(/[&;]/,$param_string);
      foreach (@pairs) {
          my($p,$v) = split('=',$_,2);
          $params{$p} = $v;
      }
  }

  $self->{request}->{params} = \%params;
  $self->{request}->{uri} = $req;
  return;
}

# are we profiling?
sub profile {
    my ($self) = @_;
    return $self->config->{agi}{profile};
}

# profiling
sub profile_mark {
    my ($self, $mark) = @_;
    return unless $self->profile;
    
    $self->_profiler(Profile::Log->new);
}
sub profile_did {
    my ($self, $mark) = @_;
    return unless $self->profile;
    
    $self->_profiler->did($mark);
    $self->log(3, "PROFILER: " . $self->_profiler->logline);
}
sub build_profiler {
    my ($self) = @_;
    return Profile::Log->new;
}


# parse uri
sub _parse_request_uri {
    my ($self, $uri_in) = @_;
    
    # split up uri
     my($class, $method, $param_string) = $uri_in
         =~ m{ (?: agi://(?:[-\w.:]+) )?  # scheme, host, port
                / ([^/]*)?                # class
                / ([^?]*)?                # method
                 \?? (.*)                 # params
             }smxi;
                
    return ($class, $method, $param_string);
}

# server is loaded, do initial setup now
sub pre_loop_hook {
    my ($self) = @_;

    $self->setup;
    return;
}

sub pre_server_close_hook {
    my ($self) = @_;

    $self->debug('pre_server_close hook called');
    return if ! $self->speech_engine_loaded;
    $self->agi->exec('SpeechDestroy');
    $self->speech_engine_loaded(0);
    return;
}

# overridden from Asterisk::FastAGI
sub dispatch_request {
    my $self = shift;

    my $uri = $self->{request}{uri};
    unless ($uri) {
        return $self->error("Got dispatch_request with no URI specified");
    }

    $self->log(2, "Dispatching request for $uri");

    unless ($self->prepare_request) {
        $self->error("prepare_request failed, exiting");
        return;
    }

    my $pretty_invocation = $uri . join (q{ }, %{$self->{request}->{params}});
    eval { $self->forward($uri, %{$self->{request}->{params}}); };

    if ($@) {
    	my $event = $@;

        $self->log(3, "Dispatch to $uri threw an event: $event");

    	if ($event->isa('Asteryst::AGI::UserGaveCommand')) {
    	    $self->error("Uncaught user command from $pretty_invocation", $event->command, 'with score', $event->score);
    	} elsif ($event->isa('Asteryst::AGI::SpeechEngineNotReady')) {
    	    $self->error($event->description . '.', "$pretty_invocation aborted");
    	} elsif ($event->isa('Asteryst::AGI::SpeechBackgroundFailed')) {
    	    $self->error("SpeechBackground failed; $pretty_invocation aborted");
    	} else {
    	    my $error_message;
    	    if (ref $event) {
    		$error_message = Dumper($event);
    	    } else {
    		$error_message = $event;
    	    }
    	    $self->error("$pretty_invocation failed.  Error message:  $error_message");
    	}

    	# No good.  Devel::StackTrace doesn't let us peek into the eval.
    	#my $trace = Devel::StackTrace->new->as_string;
    	#$self->debug($trace);
    }

    $self->finalize_request;
}

=head2 forward

my @retvals;
eval { @retvals = $self->forward('/controller_name/method_name', $arg1, $arg2); }

or

my $retval;
eval { $retval = $self->forward('/controller_name/method_name', $arg1, $arg2); }

Executes a controller method; returns the retval of that method.  You
can do this in scalar or list context, and L<forward()> will do the right thing.

If the target method throws exceptions, L<forward()> will pass them along,
so you should always call L<forward()> in an eval if you wish to do error handling.  This is especially
important in Asteryst::AGI-land because user input events are modeled as
exceptions.

Controller methods may themselves call L<forward()>.  For instance,
Asteryst::AGI::Playlist->play might invoke Asteryst::AGI::Comment->play under
certain conditions, like this:

=over 4
$c->forward('/Comment/play, @some_args);
=back

=cut
sub forward {
    my ($self, $path, @params) = @_;
    
    # don't do anything if "detached"
    return if $self->detached;

    my ($class, $method) = $self->_parse_request_uri($path);
    unless ($class && $method) {
        $self->fatal_detach("Failed to parse URI $path");
    }

    $self->debug("Forwarding to $path");

    unless ($self->loaded_controllers) {
        $self->loaded_controllers({});
    }

    # load controller singleton
    my $controller;
    if ($self->loaded_controllers->{$class}) {
        $controller = "Asteryst::AGI::Controller::$class"->instance;
    } else {
        $controller = "Asteryst::AGI::Controller::$class"->initialize({
            context => $self,
        });
            
        $self->loaded_controllers->{$class} = $controller;
    }

    return $controller->$method($self, @params);
}

# parse an incoming AGI request from asterisk
sub _agi_parse {
  my $self = shift;

  # Create an instance of our AGI interface
  $self->agi(Asteryst::CoolAGI->new);

  # Parse the request.
  my %input = $self->agi->ReadParse();
  $self->{server}{input} = \%input;
}

sub sanitize_phone {
    my ($class, $num) = @_;

    return undef unless $num;
    $num =~ s/\D//g;    # strip out non-digit chars

    # should be no greater than 16 digits and no less than 3
    my $length = length $num;
    return undef unless $length <= 16 && $length >= 3;

    # if it's 10 digits and doesn't start with a 0 or 1, assume it is
    # a U.S. number without country code
    if ($length == 10 && $num !~ m/^[01]/) {
        $num = "1$num";
    }

    return $num;
}


# overloaded version of Asterisk::AGI, used for sending/receiving commands to asterisk
package Asteryst::CoolAGI;

use parent 'Asterisk::AGI';
use autodie ':io';

sub _execcommand {
	my ($self, $command, $fh) = @_;

    my $oldfh;
    # since asterisk communication happens over STDOUT, we want 
    # to make extra-sure we aren't printing anything on STDOUT.
    my $unselect = sub {
        my $ret = shift;
        my $stderr = \*STDERR;
        select $stderr;
        return $ret;
    };

	$fh = \*STDOUT if (!$fh);

	$oldfh = select ((select ($fh), $| = 1)[0]);

	return $unselect->(-1) if (!defined($command));

	print STDERR "_execcommand: '$command'\n" if ($self->_debug>3);

	my $res = print $fh "$command\n";
	return $unselect->($res);
}

1;
