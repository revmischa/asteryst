package Asteryst::AGI::Controller::Subscription;

use Moose;
    extends 'Asteryst::AGI::Controller';
    
use Carp qw/croak/;
    
sub create_subscription {
    my ($self, $c, $feed) = @_;
    
    croak "No feed specified" unless $feed;
    
    # subscribe caller
    my $subscr = $c->schema->resultset('Subscription')->subscribe_caller_to_feed(
        caller => $c->caller,
        feed   => $feed,
    );
	
	return $subscr;
}

# find and deactivate a caller's subscription to $feed
sub remove_subscription_for_feed {
    my ($self, $c, $feed) = @_;
    
    croak "No feed specified" unless $feed;
    
    my $subscr = $c->schema->resultset('Subscription')->find({
        caller    => $c->caller->id,
        audiofeed => $feed->id,
    });
    
    return unless $subscr;
    return $self->remove_subscription($c, $subscr);
}

# deactivate a subscription
sub remove_subscription {
    my ($self, $c, $subscr) = @_;
    
    $subscr->update({ unsubscribedflag => 1 });
    
    # log it
    $c->log_action('unsubscribe on phone', {
		audiofeed => $subscr->audiofeed->id,
	});
	
	return $subscr;
}
    
1;
