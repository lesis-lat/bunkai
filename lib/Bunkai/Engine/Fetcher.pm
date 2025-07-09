package Bunkai::Engine::Fetcher;

use 5.034;
use strict;
use warnings;

use Exporter qw(import);
use MetaCPAN::Client;
use Try::Tiny;

our @EXPORT_OK = qw(fetch_latest_version);
our $VERSION   = '0.0.2';

sub fetch_latest_version {
    my ($module_name) = @_;

    my $mcpan = MetaCPAN::Client->new();
    my $version;

    try {
        my $module = $mcpan->module($module_name);
        $version = $module ? $module->version : undef;
    }
    catch {
        $version = undef;
    };

    return $version;
}

1;