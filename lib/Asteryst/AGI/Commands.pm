# Base class for sets of commands, voice/DTMF

package Asterysk::AGI::Commands;

use Moose;
use namespace::autoclean;

# dtmf / voice
sub mode {
    my ($class, $match) = @_;
    
    return 'unknown' unless $match;
    
    return $match =~ /^\d+$/ ? 'dtmf' : 'voice';
}

__PACKAGE__->meta->make_immutable;
