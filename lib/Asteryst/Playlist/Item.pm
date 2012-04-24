package Asteryst::Playlist::Item;

use Moose;
use Carp qw/croak/;

has playlist => (
    is => 'rw',
    isa => 'Asteryst::Playlist',
    required => 1,
);

has subscription => (
    is => 'rw',
    isa => 'Asteryst::Schema::AsterystDB::Result::Subscription',
);

has content => (
    is => 'rw',
    isa => 'Asteryst::Schema::AsterystDB::Result::Content',
    lazy => 1,
    builder => 'build_content',
);

has content_id => (
    is => 'rw',
    isa => 'Int',
);

has last_start_time => (
    is => 'rw',
    clearer => 'clear_start_time',
    predicate => 'has_started_listening',
);

has last_stop_time => (
    is => 'rw',
    predicate => 'has_stopped_listening',
    clearer => 'clear_stop_time',
);

has 'has_logged_listen' => (
    is => 'rw',
    isa => 'Bool',
    default => 0,
);


# lazy load content if we have content_id
sub build_content {
    my ($self) = @_;

    return undef unless $self->content_id;
    my $content = $self->playlist->rs('Content')->find($self->content_id);
    return $content;
}

sub caller {
    my ($self) = @_;
    return $self->subscription->caller;
}

sub feed {
    my ($self) = @_;
    return unless $self->has_feed_item;
    return $self->feed_item->audiofeed;
}

sub comments {
    my ($self) = @_;
    return unless $self->feed_item;
    return $self->feed_item->comments;
}

sub feed_item { undef }

sub has_feed_item {
    my $self = shift;

    return $self->feed_item ? 1 : 0;
}

sub reset_offset {
    my ($self) = @_;
    
    $self->content->offset_in_seconds(0);
    $self->content->perfect_memory(0);
}

sub record_offset {
    my $now = time();
    my ($self, $args_ref) = @_;
    my $debug = $args_ref->{debug};
    my $extra_seconds = $args_ref->{with_extra_seconds} || 0;

    $self->last_start_time
        or croak 'last_start_time is not set, but record_offset() was called';
    $self->last_stop_time
        or croak 'last_stop_time is not set, but record_offset() was called';
    my $offset = $self->last_stop_time - $self->last_start_time + $extra_seconds;
    print STDERR "record_offset:  adding $offset seconds\n" if $debug;

    $self->content->add_offset_seconds($offset);
    return;
}

sub started_listening {
    my $now = time();
    my ($self, $args_ref) = @_;
    my $debug = $args_ref->{debug} || 0;

    print STDERR "started_listening:  time is $now\n" if $args_ref->{debug};
    croak 'last_start_time is set, but started_listening was called' if $self->has_started_listening;
    croak 'last_stop_time is set,  but started_listening was called' if $self->has_stopped_listening;

    $self->last_start_time($now);

    return;
}

sub stop_timer {
    my $now = time();
    my ($self, $args_ref) = @_;
    my $debug = $args_ref->{debug} || 0;

    print STDERR "stop_timer:  time is $now\n" if $debug;
    croak 'last_stop_time is already set' if $self->has_stopped_listening();

    # this is helpful for diagnosing errors. unfortunately it causes stuff to die more often than we'd like right now
    croak 'Timer was never started, but stopped_listening was called' if (! $self->has_started_listening);

    $self->last_stop_time($now);
    my $listen_length = $now - $self->last_start_time;
    print STDERR "stop_timer:  listen length was $listen_length\n" if $debug;
    if ($self->has_feed_item) {
        $self->feed_item->increment_total_voice_listen_length($listen_length);
    }

    return;
}

sub stopped_listening {
    my ($self) = @_;
    $self->stop_timer() unless $self->has_stopped_listening();
}

sub reset_timer {
    my ($self) = @_;

    $self->clear_start_time();
    $self->clear_stop_time();

    return;
}

sub add_to_listen_length {
    my ($self, $seconds) = @_;
    return unless $self->has_feed_item();
    $self->feed_item->increment_total_voice_listen_length($seconds);
    return;
}

sub perfect_memory {
    my $self = shift;

    if ($_[0] && $self->content) {
        return $self->content->perfect_memory($_[0]);
    }
    return $self->content ? $self->content->perfect_memory : undef;
}

# wrap in subclasses
sub mark_heard {
    my ($self) = @_;
    $self->content->perfect_memory(0) if $self->content;
}
sub subscribe_action {
    croak "Playlist::Item->subscribe_action() called on base class!";
}

sub is_share          { 0 }
sub is_feed_item      { 0 }
sub is_share_intro    { 0 }
sub is_recommendation { 0 }
sub is_direct_connect { 0 }
sub is_related        { 0 }
sub is_comment        { 0 }
sub is_quikhit        { 0 }

__PACKAGE__->meta->make_immutable;
