package Asteryst::AGI::Commands::YesNo;

use Moose;
extends 'Asteryst::AGI::Commands';

sub yes          { return qr[\A 1 | (true) \Z]smx }
sub no           { return qr[\A 2 | (false) \Z]smx }

no Moose;
__PACKAGE__->meta->make_immutable;
