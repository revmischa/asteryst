package Asterysk::AGI::Commands::Comments;

use Moose;
extends 'Asterysk::AGI::Commands';

sub leave_comment { return qr[\A   1   |   leave_comment  \Z]smx }
sub go_back       { return qr[\A   2   |   go_back        \Z]smx }

no Moose;
__PACKAGE__->meta->make_immutable;
