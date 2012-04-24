package Asteryst::AGI::Session;

# this class stores contextual information for a voice app call

use Moose;

has session_id => (
    is => 'rw',
    isa => 'Str',
);

has has_played_ad => (
    is => 'rw',
    isa => 'Bool',
);

has needs_virgin_greeting => (
    is => 'rw',
    isa => 'Bool',
    clearer => 'clear_needs_virgin_greeting',
);

has subscribed_feeds => (
    is => 'rw',
    isa => 'ArrayRef',
    default => sub { [] },
);

has context => (
    is => 'rw',
    isa => 'Str',
);

has last_command => (
    is => 'rw',
    isa => 'RegexpRef',
);

has agi => (
    is => 'rw',
    isa => 'Asteryst::AGI',
    required => 1,
);

no Moose;
__PACKAGE__->meta->make_immutable;
