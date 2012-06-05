package Asteryst::AGI::Controller::AMT;

use Moose;
extends 'Asteryst::AGI::Controller';

use AnyEvent;
use AnyEvent::IRC::Client;

sub LOAD_CONTROLLER {
    my ($self, $c, %args) = @_;

    $c->log(4, "Loading AMT controller");
}

# someone is calling the space
sub ring_space {
    my ($self, $c) = @_;

    $c->log(3, "Someone is calling the space!");
    $c->forward('/AMT/irc_notify');
    $c->agi->exec('Dial', 'SIP/wooster&SIP/obitalk');
}

# fork, connect to irc, let people know, exit
sub irc_notify {
    my ($self, $c, %args) = @_;

    fork and return;

    my $cv = AnyEvent->condvar;
    my $con = new AnyEvent::IRC::Client;

    $con->reg_cb(disconnect => sub { $cv->broadcast });
    $con->send_srv(
        PRIVMSG => '#ttt',
        "Hello there I'm the cool AnyEvent::IRC test script!"
    );
    $con->reg_cb (
        sent => sub {
            if ($_[2] eq 'PRIVMSG') {
                $con->disconnect('done');
            }
        }
    );
    $con->connect("irc.hardchats.com", 6667, { nick => 'ToyFone' });
    $cv->wait;
    $con->disconnect;
}

1;
