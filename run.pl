#!/usr/bin/env perl

use strict;
use warnings;

use Config::JFDI;
use lib "lib";
use Asteryst::AGI;

run();

sub run {
    local $| = 1; # autoflush.  Necessary for the FastAGI protocol to
                  # work properly.

    my $config = Config::JFDI->new(name => "asteryst")->load;

    my $port       =  $ARGV[0] || $config->{agi}{fastagi_port} || 4573;
    my $log_level  =  $ARGV[1] || $config->{agi}{log_level}    || 3;
    my $log_file   =  $config->{agi}{log_file};
    print STDERR "Starting up Lexy FastAGI service on port $port:  log level $log_level, log file $log_file\n";
    Asteryst::AGI->run(
        port => $port,
        log_level => $log_level,
        log_file => $config->{agi}{log_file},
    );
}
