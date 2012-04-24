# This module enables functionality via the HTTP content server

package Asteryst::ContentSaver;

use Moose;
use namespace::autoclean;
use Carp qw/croak/;
use XML::Simple;
use LWP::UserAgent;

has 'api_base' => (
    is => 'rw',
    isa => 'Str',
    required => 1,
);

sub save_episode {
    my ($self, $caller, $feed, $contentref) = @_;
    
    croak 'no content passed to save_episode' unless $contentref;
    
	my $params = {
	    feedId => $feed->id,
    	content => $$contentref,
    	ani => $caller->phonenumber,
    };

    return $self->content_server_request('save-wav', $params);
}

sub save_draft {
    my ($self, $caller, $feed, $contentref) = @_;
    
    croak 'no content passed to save_draft' unless $contentref;
    
	my $params = {
	    feedId => $feed->id,
	    draft => 1,
    	content => $$contentref,
    	ani => $caller->phonenumber,
    };

    return $self->content_server_request('save-wav', $params);
}

# posts data to the content server, returns a Response object
sub content_server_request {
    my ($self, $uri, $params) = @_;
    
	my $item_id = eval {
	    my $ua = LWP::UserAgent->new(timeout => 240);
	    my $api_base = $self->api_base;
    	my $api_endpoint = "$api_base/$uri";
        my $http_response = $ua->post($api_endpoint, $params);
        
        unless ($http_response->is_success) {
            die $http_response->status_line;
        }
        
        my $resp = XMLin($http_response->content);
        
        if (defined $resp->{status} && $resp->{status} == 0) {
            # success
            my $item_id = $params->{draft} ? $resp->{draft} : $resp->{item};

            unless ($item_id) {
                die "Failed to get item id from " . $http_response->content;
            }

            return $item_id;
        } else {
            die $resp->{message} || $http_response->content;
        }
	};
	
	if ($@ || ! $item_id) {
	    return Asteryst::ContentSaver::Response->new(
	        is_success => 0,
	        error_message => $@,
	    );
	}

    return Asteryst::ContentSaver::Response->new(
        is_success => 1,
        item_id => $item_id,
    );
}

__PACKAGE__->meta->make_immutable;


## Minimal class to describe a content server response

package Asteryst::ContentSaver::Response;

use Moose;
use namespace::autoclean;

has 'is_success' => (
    is => 'rw',
    isa => 'Bool',
    required => 1,
);

has 'error_message' => (
    is => 'rw',
);

has 'content_id' => (
    is => 'rw',
    isa => 'Int',
);

has 'item_id' => (
    is => 'rw',
    isa => 'Int',
);

__PACKAGE__->meta->make_immutable;
