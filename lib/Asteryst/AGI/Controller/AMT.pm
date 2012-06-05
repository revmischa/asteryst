package Asteryst::AGI::Controller::AMT;

use Moose;
extends 'Asteryst::AGI::Controller';

sub LOAD_CONTROLLER {
    my ($self, $c, %args) = @_;

    $c->log(4, "Loading AMT controller");
}

# someone is calling the space
sub ring_space {
    my ($self, $c) = @_;

    $c->log(3, "Someone is calling the space!");
    $c->agi->exec('Dial', 'SIP/wooster&SIP/obitalk');
}

1;
