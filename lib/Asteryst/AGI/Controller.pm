package Asteryst::AGI::Controller;

use strict;
use warnings;

use MooseX::Singleton;
use Quantum::Superpositions;

has 'context' => (
    is => 'rw',
    isa => 'Asteryst::AGI',
);

has 'grammar_name' => (
    is => 'rw',
    isa => 'Str',
);

sub ctx {
    my ($self) = @_;
    return $self->context;
}

sub agi {
    my ($self) = @_;
    return $self->ctx->agi;
}

sub name {
    my $self = shift;
    my $class = ref $self; # better way to do this?
    my ($name) = $class =~ /::([^:]+)$/;
    return lc $name;
}

sub activate_grammar {
    my ($self) = @_;
    #return unless any(@{ $self->ctx->config->{agi}->{auto_activate_grammars} }) eq $self->name;
    
    my $grammar_name = $self->grammar_name || $self->name or return; 
    return $self->ctx->activate_grammar($grammar_name);
}

sub deactivate_grammar {
    my ($self) = @_;
    #return unless any(@{ $self->ctx->config->{agi}->{auto_activate_grammars} }) eq $self->name;

    my $grammar_name = $self->grammar_name || $self->name or return;
    return $self->ctx->deactivate_grammar($grammar_name);
}

sub LOAD_CONTROLLER {
  my ($self, $c) = @_;
}

sub UNLOAD_CONTROLLER {
    my ($self, $c) = @_;
    
}

no Moose;
__PACKAGE__->meta->make_immutable;
