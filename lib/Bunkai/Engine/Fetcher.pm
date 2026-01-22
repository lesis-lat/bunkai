package Bunkai::Engine::Fetcher;

use 5.034;
use strict;
use warnings;

use Exporter qw(import);
use MetaCPAN::Client;
use Try::Tiny;

our @EXPORT_OK = qw(fetch_latest_version);
our $VERSION   = '0.0.4';

sub fetch_latest_version {
    my ($module_name) = @_;

    my $metacpan_client = MetaCPAN::Client -> new();
    my $version;

    try {
        my $module = $metacpan_client -> module($module_name);
        if ($module) {
            $version = $module -> version;
        }
    }
    catch {
        $version = undef;
    };

    return $version;
}

1;
