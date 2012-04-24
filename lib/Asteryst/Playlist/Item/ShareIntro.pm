package Asteryst::Playlist::Item::ShareIntro;

use Moose;
extends 'Asteryst::Playlist::Item::Share';

use Carp qw/croak/;

sub is_share_intro { 1 }

no Moose;
__PACKAGE__->meta->make_immutable;
