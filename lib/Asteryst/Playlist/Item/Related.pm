package Asteryst::Playlist::Item::Related;

use Moose;
extends 'Asteryst::Playlist::Item::FeedItem';

use Carp qw/croak/;

sub is_related { 1 }
sub is_feed_item { 0 }

sub subscribe_action { 'subscribe to related asteryst' }

no Moose;
__PACKAGE__->meta->make_immutable;


