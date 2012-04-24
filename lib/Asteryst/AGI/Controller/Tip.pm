package Asterysk::AGI::Controller::Tip;

use Moose;
extends 'Asterysk::AGI::Controller';

our $TIP_COUNT = 10; # number of tip files

sub play_random {
    my ($self, $c) = @_;
    
    # don't play tips unless caller has > 5 visits
    return unless $c->caller->numvisits > 5;

    my $tip = int(rand($TIP_COUNT));
    $c->log(3, "Playing random tip $tip");
    $c->prompt("playcontent/sharetips/sharetip$tip");
}

1;
