package Asterysk::ContentPrecache;

use Moose;

use FindBin;
use lib "$FindBin::RealBin/../asterysk2perl/lib";
use lib "$FindBin::RealBin/../asterysk3/lib";
use lib "$FindBin::RealBin/../lib";

use Asterysk::ContentFetcher;
use Profile::Log;
use Asterysk::Model::AsteryskDB;
with 'MooseX::Getopt';

has 'debug'  => (is => 'rw', isa => 'Bool', required => 0);
has 'daemonize'  => (is => 'rw', isa => 'Bool', required => 0);
has 'expire'  => (
    is => 'rw',
    isa => 'Int',
    required => 1,
    default => 3600 * 24 * 14,  # keep content around for 14 days
);
has 'delay'  => (
    is => 'rw',
    isa => 'Int',
    required => 1,
    default => 180,  # check every 2 minutes
);
# log file
has 'log_file'  => (
    is => 'rw',
    isa => 'Str',
    required => 1,
    default => '/home/asterysk/fetch_content.log',
);
has 'logfh' => (
    is => 'rw',
);
has 'fetcher' => (
    is => 'rw',
    isa => 'Asterysk::ContentFetcher',
    lazy => 1,
    builder => 'build_fetcher',
);


sub run {
    my ($self) = @_;
    
    if ($self->daemonize) {
        print "Daemonizing...\n";
        fork and exit;
    }
    
    my $logfh = $self->open_log();
    $self->logfh($logfh);
    
    $self->_log("Daemonized") if $self->daemonize;
    
    while (1) {
        my @content_ids = $self->get_content_ids;
        
        unless (@content_ids) {
            sleep $self->delay;
            next;
        }
        
        foreach my $content_id (@content_ids) {
            $self->fetch_content($content_id);
        }
        
        $self->fetcher->delete_all_except(\@content_ids);
    }
    
    close $self->logfh if $self->logfh;

    exit 0;
}

sub build_fetcher {
    my ($self) = @_;
    
    return new Asterysk::ContentFetcher(
        expire => $self->expire,
    );
}

sub get_content_ids {
    my ($self) = @_;
    
    my $schema = Asterysk::Schema::AsteryskDB->get_connection;
    my $rs = $schema->resultset('Audiofeed');
    
    return $rs->search({
    }, {
        order_by => [qw/created/],
    })->get_column('lastcontent')->all;
}

sub fetch_content {
    my ($self, $content_id) = @_;
    
    return unless $content_id;
    $self->_log("Fetching content $content_id", 1) if $self->debug;

    my $fetcher = $self->fetcher;

    my $prof = new Profile::Log;
    my ($path, $was_cached) = eval { $fetcher->fetch_content($content_id) };
    $prof->did($was_cached ? "fetch_content_cached" : "fetch_content");

    if (! $@ && $path) {
        $self->_log("Content fetched, cached=$was_cached, id=$content_id, path=$path  " . $prof->logline, 1) if ! $was_cached || $self->debug;
    } else {
        $self->_log("ERROR: failed to fetch content $content_id: $@");
        select undef, undef, undef, 0.4;
    }
}

sub open_log {
    my ($self) = @_;
    
    my $log_file = $self->log_file;
    
    my $fh;
    unless (open $fh, ">>$log_file") {
        warn "Error opening $log_file: $!";
        $self->_log("Error opening content fetching log $log_file: $!", 1);
        $self->logfh(undef);
        return;
    }
    $self->logfh($fh);
}

sub _log {
    my ($self, $line) = @_;

    print "$line\n" unless $self->daemonize;

    return unless $self->logfh;
    print { $self->logfh } "$line\n";
}

__PACKAGE__->meta->make_immutable;
