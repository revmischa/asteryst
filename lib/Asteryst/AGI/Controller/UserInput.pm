package Asterysk::AGI::Controller::UserInput;

use Moose;
extends 'Asterysk::AGI::Controller';

use Carp qw/croak/;
use Asterysk::AGI::Events;
use Asterysk::AGI::Exceptions;

sub play_file {
    my ($self, $c, %args) = @_;
    
    my $path = $args{path};
    my $content = $args{content};
    
    if (defined $path && ! $path) {
        return Asterysk::AGI::NoPathToContent->throw(content => $content);
    }
    
    if (defined $path && ! $args{dont_check_existance} &&
         ! $c->check_if_content_path_exists($path)) {
             
        $c->log(2, "Failed existance check for $path");
        return Asterysk::AGI::MissingSoundFile->throw(content => $content, path => $path);
    }

    $c->log(4, "Playing file " . (defined $path ? $path : '(undef)'));

    if ($c->speech_enabled) {
        return $c->forward('/UserInput/speech_background', %args);
    } else {
        return $c->forward('/UserInput/background', %args);
    }
}

# play audio file while awaiting DTMF input
sub background {
    my ($self, $c, %args) = @_;
    
    # params
    my $path = $args{path};
    my $content = $args{content};
    my $timeout = $args{timeout} ? $args{timeout} * 1000 : 1; # ms, shouldn't be 0                 
    my $max_digits = $args{max_digits} || 1;

    my $bg_retval = $c->agi->get_data($path, $timeout, $max_digits);
    my $path_disp = $path || '(none)';
    $c->log(4, "AGI->get_data($path_disp, $timeout, $max_digits) returned: " . ($bg_retval || '(non-true)'));
    
    if ($c->hungup) {
        $c->log(2, "Caller hung up during UserInput/background");
        Asterysk::AGI::UserHungUp->throw;
        return;
    }
    
    if (defined $bg_retval) {
        # this is a hack to let us read two digits if $max_digits==2
        # and timeout<1s, due to the fact that we can't specify
        # separate timeouts for end-of-playback vs digit-pressed to
        # GET DATA from AGI-land, even though it supports them by
        # default
        if ($max_digits == 2 && $timeout < 1000) {
            # read second digit
	    # wait two seconds for second digit
            my $second_retval = $c->agi->get_data($path, 2, 1);
            $bg_retval .= $second_retval if defined $second_retval && $second_retval != -1;
        }

        Asterysk::AGI::UserGaveCommand->throw(
            command => $bg_retval,
            score   => 1000,
        );
    }
}

# play audio file while awaiting voice or DTMF input
sub speech_background {
    my ($self, $c, %args) = @_;
    my $path = $args{path};
    my $content = $args{content};
    my $debug = 1;
    my $timeout = $args{timeout} || 0;

    if (! $path) {
        return Asterysk::AGI::NoPathToContent->throw(content => $content);
    }

    # make sure path exists
    unless ($c->check_if_content_path_exists($path)) {
        return Asterysk::AGI::MissingSoundFile->throw(content => $content, path => $path);
    }

    $self->_speech_start($c);
    my $sb_retval = $c->agi->exec('SpeechBackground', "$path, $timeout");
    $c->log(3, "SpeechBackground($path) == $sb_retval") if $debug;

    if ($sb_retval != 0) {
        # speechbackground failed, either speech engine error or user hung up

        if ($c->hungup) {
            Asterysk::AGI::UserHungUp->throw();
        } else {
            Asterysk::AGI::SpeechBackgroundFailed->throw();
        }
    } else {
        my ($command, $score, $spoke, $status) = $self->_dump_speech_results($c);
        if ((! $command) && (! $score)) {

            # speechbackground completed without returning any spoken
            # commands either the file played from start to finish
            # without getting input, or there was a failure.

            if ($c->hungup) {
                $c->log(2, "Caller hung up during UserInput/speech_background");
                Asterysk::AGI::UserHungUp->throw();
            }

            # finished listening normally, channel is still active
        } else {
            $c->log(2, qq[command '$command'; score '$score']) if $debug;
            
            Asterysk::AGI::UserGaveCommand->throw(
                command => $command,
                score   => $score,
            );
        }
    }
}

# play a prompt, wait for $timeout for user to enter $max_digits digits
sub get_dtmf_input {
    my ($self, $c, $prompt, $timeout, $max_digits) = @_;
    
    $timeout ||= 60;
    $max_digits ||= 1;
    
    # look up path on filesystem if not absolute
    my $prompt_path = $prompt;
    $prompt_path = $c->forward('/Prompt/get_path', $prompt)
        if defined $prompt && $prompt !~ /^\//;
    
    eval {
        $c->forward('/UserInput/play_file',
            dont_check_existance => 1,
            path => $prompt_path,
            timeout => $timeout,
            max_digits => $max_digits,
        );
    };
        
    if ($@) {
        my $event = $@;
        
        if ($event->isa('Asterysk::AGI::UserGaveCommand')) {
            $c->log(4, "get_dtmf_input returned: $event");
            return $event->command;
        } else {
            $c->log(3, "got unknown event from play_file in get_dtmf_input: $event");
            return undef;
        }
    }
    
    # timeout most likely if we got here
    $c->log(4, "got no event back from play_file in get_dtmf_input");
    return undef;
}

sub _dump_speech_results {
    my ($self, $c) = @_;
    my $command  =  $c->var(q[SPEECH_TEXT(0)]);
    my $score    =  $c->var(q[SPEECH_SCORE(0)]);
    my $spoke    =  $c->var(q[SPEECH_SPOKE]);
    my $status   =  $c->var(q[SPEECH_STATUS]);
    return ($command, $score, $spoke, $status);
}

sub _speech_start {
    my ($self, $c) = @_;

    my $sb_retval = $c->agi->exec('SpeechStart');
    $c->log(4, "SpeechStart == $sb_retval") if 1;
}

#no Moose;
#__PACKAGE__->meta->make_immutable();

1;
