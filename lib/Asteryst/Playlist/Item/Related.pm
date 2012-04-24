package Asterysk::Playlist::Item::Related;

use Moose;
extends 'Asterysk::Playlist::Item::FeedItem';

use Carp qw/croak/;

sub is_related { 1 }
sub is_feed_item { 0 }

sub subscribe_action { 'subscribe to related asterysk' }

no Moose;
__PACKAGE__->meta->make_immutable;


