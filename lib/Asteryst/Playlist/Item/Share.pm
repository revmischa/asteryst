package Asterysk::Playlist::Item::Share;

use Moose;
extends 'Asterysk::Playlist::Item';

use Carp qw/croak/;

has share => (
    is => 'rw',
    isa => 'Asterysk::Schema::AsteryskDB::Result::Audioshare',
    required => 1,
);

sub feed_item {
    my ($self) = @_;
    
    return $self->share->content->feed_item;
}

after mark_heard => sub {
    my ($self) = @_;
    
    my $share = $self->share;
    $share->update({
	    dateheard => \ 'NOW()',
    });
};

sub is_share { 1 }

sub subscribe_action { 'subscribe to share' }

no Moose;
__PACKAGE__->meta->make_immutable;
