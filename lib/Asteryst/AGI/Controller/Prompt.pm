package Asteryst::AGI::Controller::Prompt;

use Moose;
    extends 'Asteryst::AGI::Controller';

use Carp;

use Asteryst::AGI::Events;
use Asteryst::AGI::Exceptions;
use aliased 'Asteryst::AGI::Commands::YesNo' => 'YesNoCommand';

sub prompt_root {
    my ($self, $c) = @_;
    
    return $c->config->{agi}{prompt_directory} or die "prompt directory not configured";
}

# get full path to a prompt file
sub get_path {
    my ($self, $c, $file) = @_;
    return $self->prompt_root($c) . '/' . $file;
}

sub no_caller_id {
    my ($self, $c) = @_;
    $self->play($c, 'callerid_blocked');
}

sub fatal_error {
    my ($self, $c) = @_;
    $self->play($c, 'error');
}

sub greeting {
    my ($self, $c) = @_;
    
    if ($c->caller->numvisits <= 1) {
        # virgin caller
        $c->log(3, "Playing virgin greeting prompt");
        $c->prompt('greetings/intro-virgin');
    } else {
        $c->log(3, "Playing greeting prompt");
        $self->play($c, 'greetings/intro');
    }
}

sub play {
    my ($self, $c, $file, $text) = @_;
    
    return unless $file;
    
    $c->debug("Playing prompt " . ($text || $file));
    $c->agi->exec('Playback', $self->get_path($c, $file));
    
    my $rv = $c->var('PLAYBACKSTATUS');
    $rv = $rv && $rv eq 'SUCCESS' ? 1 : 0;
    $c->log(3, "Playback retval = " . ($rv ? "success" : "failure"));
    
    if (! $rv && $text) {
        # failed to play that file, if there's a textual equivilant then use TTS on that
        return $c->forward('/Prompt/tts', $text);
    }
    
    return $rv;
}

# say something, using Text-To-Speech (flite)
sub tts {
    my ($self, $c, $text) = @_;

    return unless $text;

    $c->log(3, "Using TTS for '$text'");
    return unless $c->config->{agi}{use_tts};

    my $tts_app = $c->config->{agi}{tts_app} || 'Flite';
    $c->agi->exec($tts_app, "$text");
    return 1;  # assume success
}

=head2

L<wait_to_unpause()> - plays a file and waits for input, as in background, but
accepts only DTMF input; on voice input, it does nothing (i.e. keeps waiting).

RETURN VALUE

    The digit that was pressed.

DIAGNOSTICS

    =item croak()'s with a string exception if the pause_message_rel_path
     or the timeout named arg is undefined.

    =item Dies with a Asteryst::AGI::Exception::StreamFileFailed object if
    the STREAM FILE fails (i.e. the AGI peer sends result=-1)

=back

=cut
sub wait_to_unpause {
    my ($self, $c) = @_;
    my $digits = '1234567890'; # unpause on any digit
    my $agi = $c->agi;
    my $debug = 1;

    my $pause_message_rel_path = 'pause';
    my $timeout_in_seconds = $c->config->{agi}{pause_timeout};
    my $pause_message_path = $self->get_path($c, $pause_message_rel_path);

    my $start_time = time();
    my $stream_retval = $agi->stream_file($pause_message_path, $digits, 0);
    if ($stream_retval == -1) {
        #$c->debug() if $debug;
        Asteryst::AGI::Exception::StreamFileFailed->throw(path => $pause_message_path);
    } elsif ($stream_retval == 0) {
        # We finished streaming the file, but the user didn't press any of our
        # recognized digits.  Keep waiting.
        my $wait_retval = $agi->wait_for_digit($digits, 1000 * ($timeout_in_seconds - (time() - $start_time)));
        if ($wait_retval == 0) {
            # Timed out.
            $c->detach();
            Asteryst::AGI::Exception::UnreachableCodeReached->throw();
        } elsif ($wait_retval == -1) {
            Asteryst::AGI::Exception::WaitForDigitFailed->throw();
        } else {
            return $wait_retval; # the digit that was pressed
        }
    } else {
        return $stream_retval;   # the digit that was pressed
    }

    Asteryst::AGI::Exception::UnreachableCodeReached->throw();
}

# play $prompt, wait for caller to say yes or no, return bool
sub yes_or_no {
    my ($self, $c, $prompt, $timeout) = @_;
    
    $timeout ||= 60;
    
    $c->push_grammar('yesno');
    
    my $prompt_path = $self->get_path($c, $prompt);
    eval {
        $c->forward('/UserInput/play_file', path => $prompt_path, timeout => $timeout);
    };
    
    my $yorn;
    
    if ($@) {
        my $event = $@;
        
        if ($event->isa('Asteryst::AGI::UserGaveCommand')) {
            $c->log(4, "yes_or_no command: $event");
            
            if ($event->command =~ YesNoCommand->yes) {
                $yorn = 1;
            } elsif ($event->command =~ YesNoCommand->no) {
                $yorn = 0;
            } else {
                $c->error("got unknown YesNoCommand command: " . $event->command);
            }
        } else {
            $c->log(1, "got unknown event from play_file in yes_or_no: $event");
        }
    } else {
        # timeout most likely
        $c->log(4, "got no event back from play_file in yes_or_no");
    }
    
    $c->pop_grammar;
    
    return $yorn;
}

# earcon to inform the user the app is thinking
# calls background below
sub play_busy {
    my ($self, $c) = @_;

    # broken
    $c->background($self->get_path($c, 'busy'));
}

# disabled
sub background {
    my ($self, $c, $file) = @_;
    
    return;
    
    # turns out this doesn't work from AGI-land! it blocks until it finishes playing the file :(
    $c->agi->exec('Background', $file);
}

# quick playback of audio notification clips
sub earcon {
    my ($self, $c, $earcon) = @_;
    $c->prompt("earcons/$earcon");
}

1;
