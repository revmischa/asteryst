package Asteryst::Playlist::Item::FeedItem;

use Moose;
extends 'Asteryst::Playlist::Item';

use Carp qw/croak/;

has feed_item_id => (
    is => 'rw',
);

has subscription_id => (
    is => 'rw',
);

has feed_item => (
    is => 'rw',
    isa => 'Asteryst::Schema::AsterystDB::Result::Audiofeeditem',
    lazy => 1,
    builder => 'build_feed_item',
);

sub subscription {
    my ($self) = @_;
    return unless $self->subscription_id;
    return $self->playlist->rs('Subscription')->find($self->subscription_id);
}

# lazy load audioFeedItem if we have feed_item_id
sub build_feed_item {
    my ($self) = @_;
    
    if ($self->feed_item_id) {
        # look up feed item from id
        my $feed_item = $self->playlist->rs('Audiofeeditem')->find($self->feed_item_id);
        
        if ($feed_item) {
            return $feed_item;
        }
    } else {
        # if we don't have feed_item_id, maybe we have a content row we can find it from
        
        my $content = $self->content;
        return undef unless $content; # nope, hopeless
        
        my $feed_item = $content->feed_item;
        return $feed_item if $feed_item;
    }
    
    return undef;
}

after mark_heard => sub {
    my ($self) = @_;

    return unless $self->subscription;

    $self->subscription->update({ heardlastcontent => 1 });
    $self->feed_item->increment_listen_count;

    return;
};

sub is_feed_item { 1 }

sub subscribe_action { undef }  # this doesn't really happen

no Moose;
__PACKAGE__->meta->make_immutable;
