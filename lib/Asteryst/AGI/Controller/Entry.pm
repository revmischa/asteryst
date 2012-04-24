package Asterysk::AGI::Controller::Entry;

use Moose;
extends 'Asterysk::AGI::Controller';

sub playlist {
    my ($self, $c) = @_;

    # bleep bloop
    $c->earcon('welcome');

    # check if they called a direct connect #
    $c->forward('/DirectConnect/start');
    
    # load and play playlist
    $c->forward('/Playlist/play');
}

sub ad_test {
    my ($self, $c) = @_;

    $c->forward('/Ad/play');
}


sub publish {
    my ($self, $c) = @_;

    # bleep bloop
    $c->prompt('earcons/welcome');

    $c->forward('/Publish/entry');
}


#no Moose;
#__PACKAGE__->meta->make_immutable;

1;
