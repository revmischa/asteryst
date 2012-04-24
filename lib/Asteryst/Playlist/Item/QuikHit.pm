package Asteryst::Playlist::Item::QuikHit;

use Moose;
extends 'Asteryst::Playlist::Item::FeedItem';

use Carp qw/croak/;

sub is_quikhit { 1 }

no Moose;
__PACKAGE__->meta->make_immutable;
