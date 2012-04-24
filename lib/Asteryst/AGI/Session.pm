package Asterysk::AGI::Session;

# this class stores contextual information for a voice app call

use Moose;

use Asterysk::AGI::Controller::Comments;

has session_id => (
    is => 'rw',
    isa => 'Str',
);

has introduced_related_asterysks => (
    is => 'rw',
    isa => 'Bool',
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

has introduced_recommendations => (
    is => 'rw',
    isa => 'Bool',
);

has checked_quikhit => (
    is => 'rw',
    isa => 'Bool',
    default => 0,
);

has introduced_comments => (
    is => 'rw',
    isa => 'Bool',
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

has caller_can_publish_multiple_rtqs => (
    is => 'rw',
    isa => 'Bool',
);


has agi => (
    is => 'rw',
    isa => 'Asterysk::AGI',
    required => 1,
);

# this might be a little too magical, should maybe use push/pop grammar instead
around context => sub {
    my ($orig, $self, $ctx) = @_;
    
    my $old_ctx = $self->$orig();
    return $old_ctx unless defined $ctx;
    
    $self->$orig($ctx);
    $self->agi->debug("Entering context $ctx");
    
    return unless $self->agi->speech_enabled;

    my $cmt_controller = Asterysk::AGI::Controller::Comments->instance;
    my $playlist_controller = Asterysk::AGI::Controller::Playlist->instance;
    
    if ($old_ctx ne 'comments' && $ctx eq 'comments') {
      $playlist_controller->deactivate_grammar;
      $cmt_controller->activate_grammar;
    } elsif ($old_ctx eq 'comments' && $ctx ne 'comments') {
      $cmt_controller->deactivate_grammar;
      $playlist_controller->activate_grammar;
    }
};

sub in_related_context {
    my ($self) = @_;
    return $self->context eq 'related';
}

sub in_comments_context {
    my ($self) = @_;
    return $self->context eq 'comments';
}

no Moose;
__PACKAGE__->meta->make_immutable;
