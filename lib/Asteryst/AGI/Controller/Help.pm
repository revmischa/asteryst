package Asterysk::AGI::Controller::Help;

use Moose;
extends 'Asterysk::AGI::Controller';

use Asterysk::AGI::Commands::Navigation;
use Asterysk::AGI::Controller::UserInput;
use Asterysk::AGI::Events;

use Asterysk::Common;
use Asterysk::Notification;

sub playback {
    my ($self, $c) = @_;
    $c->session->context('help');
    $c->push_grammar('help');

    $c->prompt('earcon/asterysk');
    eval {
        # Play the list of commands.
        my $path = Asterysk::AGI::Controller::Prompt->get_path($c, 'asteryskhelp/prompt1');
        $c->forward('/UserInput/play_file', path => $path); #TODO:  Re-record to remove the reference to the Share command
    };
    if ($@) {
        my $event = $@;
        if ($event =~ Asterysk::AGI::Commands::Navigation->text_me) {
            $c->forward('/Help/text_me');

            # "OK, I've sent you a text with more info.  If you meant to share,
            # that command is now '11'."
            $c->prompt('textme/text');
        } else {
            die $event;
        }
    } else {
        # The caller listened all the way through.
        
    }
}

sub text_me {
    my ($self, $c) = @_;

    Asterysk::Notification->textme($c->caller);

    return;
}

1;
