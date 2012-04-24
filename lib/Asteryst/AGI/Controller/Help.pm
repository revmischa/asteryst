package Asteryst::AGI::Controller::Help;

use Moose;
extends 'Asteryst::AGI::Controller';

use Asteryst::AGI::Commands::Navigation;
use Asteryst::AGI::Controller::UserInput;
use Asteryst::AGI::Events;

use Asteryst::Common;
use Asteryst::Notification;

sub playback {
    my ($self, $c) = @_;
    $c->session->context('help');
    $c->push_grammar('help');

    $c->prompt('earcon/asteryst');
    eval {
        # Play the list of commands.
        my $path = Asteryst::AGI::Controller::Prompt->get_path($c, 'asterysthelp/prompt1');
        $c->forward('/UserInput/play_file', path => $path); #TODO:  Re-record to remove the reference to the Share command
    };
    if ($@) {
        my $event = $@;
        if ($event =~ Asteryst::AGI::Commands::Navigation->text_me) {
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

    Asteryst::Notification->textme($c->caller);

    return;
}

1;
