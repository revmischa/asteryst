package Asterysk::AGI::Commands::GiveComment;

use Moose;
extends 'Asterysk::AGI::Commands';

sub publish_comment { return qr[\A   1   |   publish_comment  \Z]smx }
sub try_again       { return qr[\A   2   |   try_again        \Z]smx }
sub cancel          { return qr[\A   \*  |   cancel           \Z]smx }

no Moose;
__PACKAGE__->meta->make_immutable;
