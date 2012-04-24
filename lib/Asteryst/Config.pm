package Asterysk::Config;

use Moose;
use namespace::autoclean;
use Config::JFDI;
use File::Basename qw(dirname);
use Carp qw/croak/;

my $config;

sub get {    
    if (! defined $config) {
        my $own_path = (caller(0))[1];
        my $own_dir  = dirname $own_path;
        my $config_path = "$own_dir/../../asterysk3";
        eval { $config = Config::JFDI->new(
            name => "Asterysk",
            path => $config_path,
        )->load; };
        my $error_string = $@; # always dies with strings, not other things.
        if ($error_string) {
            croak("Could not load Asterysk config file at $config_path. " .
                    "Error message from Config::JFDI->new: '$error_string'");
        }
    }
    
    return $config;
}

__PACKAGE__->meta->make_immutable;
