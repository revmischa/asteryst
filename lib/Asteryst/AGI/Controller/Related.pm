package Asterysk::AGI::Controller::Related;

use Moose;
extends 'Asterysk::AGI::Controller';

use Asterysk::Related;

sub get_for_feed {
    my ($self, $c, $feed) = @_;
        
    unless ($feed) {
        $c->log(2, "related/get_for_feed called with no feed");
        
        # failed prompt?
        
        return;
    }
    
    # don't return feeds the caller has already subscribed to this call
    my $subscribed_feeds = $c->session->subscribed_feeds;
    my @xcl_ids = map { $_->id } @$subscribed_feeds;
        
    my @related = Asterysk::Related->related_to_feed(
        feed    => $feed,
        caller  => $c->caller,
        limit   => 10,
        exclude => \@xcl_ids,
    );
    
    return @related;
}

1;
