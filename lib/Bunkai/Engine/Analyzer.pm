package Bunkai::Engine::Analyzer;

use 5.034;
use strict;
use warnings;

use version;
use Exporter qw(import);

use Bunkai::Engine::Fetcher qw(fetch_latest_version);

our @EXPORT_OK = qw(analyze_dependencies);
our $VERSION   = '0.0.3';

sub enrich_dependency {
    my ($dependency) = @_;

    my $latest_version = fetch_latest_version( $dependency->{module} );
    my $is_outdated    = 0;

    if ( $dependency->{has_version} && defined $latest_version ) {
        my $current_v = version->new( $dependency->{version} );
        my $latest_v  = version->new($latest_version);

        if ( defined($current_v) && defined($latest_v) && ( $current_v < $latest_v ) ) {
            $is_outdated = 1;
        }
    }

    return +{
        %{$dependency},
        latest_version => $latest_version,
        is_outdated    => $is_outdated,
    };
}

sub analyze_dependencies {
    my ($dependencies) = @_;

    return [ map { enrich_dependency($_) } @{$dependencies} ];
}

1;
