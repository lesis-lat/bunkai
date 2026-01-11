#!/usr/bin/env perl

use 5.034;
use strict;
use warnings;

use Test::More;
use Test::MockModule;
use lib '../lib/';

use Bunkai::Engine::Analyzer qw(analyze_dependencies);

our $VERSION = '0.0.4';

my $analyzer_mock = Test::MockModule -> new('Bunkai::Engine::Analyzer');

$analyzer_mock -> redefine(
    'fetch_latest_version',
    sub {
        my ($module) = @_;
        my %versions = (
            UpToDate   => '1.00',
            Outdated   => '2.00',
            BadVersion => '1.00',
        );
        return $versions{$module};
    }
);

subtest 'dependency analysis' => sub {
    my $dependencies = [
        { module => 'UpToDate',   version => '1.00', has_version => 1 },
        { module => 'Outdated',   version => '1.00', has_version => 1 },
        { module => 'NoVersion',  version => undef,  has_version => 0 },
        { module => 'NotFound',   version => '1.00', has_version => 1 },
        { module => 'BadVersion', version => 'v1',   has_version => 1 },
    ];

    my $analyzed_dependencies = analyze_dependencies($dependencies);
    my %results_by_module  = map { $_ -> {module} => $_ } @{$analyzed_dependencies};

    is( $results_by_module{UpToDate}{is_outdated}, 0, 'Up-to-date module is not marked as outdated' );
    is( $results_by_module{UpToDate}{latest_version}, '1.00', 'Up-to-date module has correct latest_version' );

    is( $results_by_module{Outdated}{is_outdated}, 1, 'Outdated module is marked as outdated' );
    is( $results_by_module{Outdated}{latest_version}, '2.00', 'Outdated module has correct latest_version' );

    is( $results_by_module{NoVersion}{is_outdated}, 0, 'Module with no version is not marked as outdated' );
    is( $results_by_module{NoVersion}{latest_version}, undef, 'Module with no version has undef latest_version' );

    is( $results_by_module{NotFound}{is_outdated}, 0, 'Module not found on CPAN is not marked as outdated' );
    is( $results_by_module{NotFound}{latest_version}, undef, 'Module not found on CPAN has undef latest_version' );

    is( $results_by_module{BadVersion}{is_outdated}, 0, 'Module with invalid version is not marked outdated' );
};

done_testing();
