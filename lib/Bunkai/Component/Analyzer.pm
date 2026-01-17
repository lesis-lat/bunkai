package Bunkai::Component::Analyzer;

use 5.034;
use strict;
use warnings;

use version;
use Exporter qw(import);

use Bunkai::Component::Fetcher qw(fetch_latest_version);

our @EXPORT_OK = qw(analyze_dependencies);
our $VERSION   = '0.0.4';

sub parse_version_value {
    my ($value) = @_;

    if ( !defined $value ) {
        return;
    }

    my $parsed_version = eval { version -> new($value) };

    if ($@) {
        return;
    }

    return $parsed_version;
}

sub enrich_dependency {
    my ($dependency) = @_;

    my $latest_version = fetch_latest_version( $dependency -> {module} );
    my $is_outdated    = 0;

    if ( $dependency -> {has_version} && defined $latest_version ) {
        my $current_version_parsed = parse_version_value( $dependency -> {version} );
        my $latest_version_parsed  = parse_version_value($latest_version);

        if ( defined $current_version_parsed
            && defined $latest_version_parsed
            && ( $current_version_parsed < $latest_version_parsed ) )
        {
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
