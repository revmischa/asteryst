package Asteryst::Playlist::Item::Recommendation;

use Moose;
extends 'Asteryst::Playlist::Item::FeedItem';

use Carp qw/croak/;

sub is_recommendation { 1 }
sub is_feed_item { 0 }

sub subscribe_action { 'subscribe to recommendation' }

no Moose;
__PACKAGE__->meta->make_immutable;
