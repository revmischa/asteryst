# this represents a feed item that is from a directconnect playlist
package Asterysk::Playlist::Item::DirectConnect;

use Moose;
extends 'Asterysk::Playlist::Item::FeedItem';

use Carp qw/croak/;

sub is_direct_connect { 1 }

sub subscribe_action { 'subscribe to direct connect quikcast' }

sub is_feed_item { 0 }

no Moose;
__PACKAGE__->meta->make_immutable;
