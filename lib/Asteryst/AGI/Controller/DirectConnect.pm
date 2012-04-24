package Asteryst::AGI::Controller::DirectConnect;

use Moose;
extends 'Asteryst::AGI::Controller';

use Asteryst::Util;

# check our DID, if it's a direct connect number mark it as such
sub start {
    my ($self, $c) = @_;
    
    $c->context('directconnect');
    
    # should be the DID
    my $dnid_orig = $c->dnid;

    # this really shouldn't happen ever i hope
    unless ($dnid_orig) {
        return $c->fatal_detach("Could not find incoming DNID!");
    }
    
    # canonicalize
    my $dnid = Asteryst::Util->sanitize_number($dnid_orig);
    unless ($dnid) {
        return $c->fatal_detach("I don't understand the phone number $dnid_orig")
            unless $c->config->{agi}{accept_developer_dids};
            
        return;
    }
    
    # look up partner for this DID
    my $partner_dc = $c->schema->resultset('Partnerdirectconnects')->find({ directconnect => $dnid });
    my $partner = $partner_dc ? $partner_dc->partner : undef;
    
    # set caller source if not set
    unless ($c->caller->source) {
        my $partner_id = $partner ? $partner->id : 1; # 1 = asteryst
        $c->caller->update({ source => $partner_id });
    }
    
    unless ($partner && $partner_dc) {
        return;
    }
    
    # this is a directconnect

    $c->log(2, 'Direct connect number=' . $dnid . ' name=' . $partner_dc->connectlabel . 
        ' to partner ' . $partner->name);
        
    $c->partner($partner);
    $c->direct_connect($partner_dc);
}

# no Moose;
# __PACKAGE__->meta->make_immutable;

1;
