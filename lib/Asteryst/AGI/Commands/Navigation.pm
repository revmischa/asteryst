package Asteryst::AGI::Commands::Navigation;

use Moose;
extends 'Asteryst::AGI::Commands';

sub text_me       { return qr[\A 1       | (text_me)       \Z]smx }
sub comments      { return qr[\A 2       | (comments)      \Z]smx }
sub related       { return qr[\A 3       | (related)       \Z]smx }

sub rewind        { return qr[\A  4      | (rewind)        \Z]smx }
sub pause         { return qr[\A  5      | (pause)         \Z]smx }
sub fast_forward  { return qr[\A  6      | (fast_forward)  \Z]smx }

sub replay        { return qr[\A  7      | (replay)        \Z]smx }
sub subscribe     { return qr[\A  8      | (subscribe)     \Z]smx }
sub play_next     { return qr[\A  9      | (play_next)     \Z]smx }
sub previous      { return qr[\A  (77)   | (previous)      \Z]smx }

sub skip_for_now  { return qr[\A  (99)   | (skip_for_now)  \Z]smx }

##########
# Hack to support returning from help without giving help
# a separate grammar.
#
# Be careful in what order you match these.  They both use 0
# as their digit version.
##########
sub help          { return qr[\A  0      | (help)          \Z]smx }
sub resume        { return qr[\A  (0)    | (resume)        \Z]smx }

no Moose;
__PACKAGE__->meta->make_immutable;
