package Bunkai::Component::Fetcher;

use 5.034;
use strict;
use warnings;

use Exporter qw(import);
use MetaCPAN::Client;
use Try::Tiny;
use Type::Params qw(signature);

use Bunkai::Types qw(ModuleName);

our @EXPORT_OK = qw(fetch_latest_version);
our $VERSION   = '0.0.4';

my $fetch_latest_version_check = signature(positional => [ModuleName]);

sub fetch_latest_version {
    my ($module_name) = @_;

    ($module_name) = $fetch_latest_version_check ->($module_name);

    my $metacpan_client = MetaCPAN::Client -> new();
    my $version;

    try {
        my $module = $metacpan_client -> module($module_name);
        if ($module) {
            if (($module -> distribution // q{}) eq 'perl') {
                return;
            }
            $version = $module -> version;
        }
    }
    catch {
        $version = undef;
    };

    return $version;
}

1;
