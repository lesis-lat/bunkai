#!/usr/bin/env perl

package main;

use 5.034;
use strict;
use warnings;

use Test::More;
use Test::MockModule;
use FindBin;
use lib "$FindBin::Bin/../../lib";
use lib "$FindBin::Bin/../lib";

use Bunkai::Component::Analyzer qw(analyze_dependencies);

our $VERSION = '0.0.4';

my $analyzer_mock = Test::MockModule -> new('Bunkai::Component::Analyzer');

$analyzer_mock -> redefine(
    'fetch_latest_version',
    sub {
        my ($module) = @_;
        my %versions = (
            UpToDate     => '1.00',
            Outdated     => '2.00',
            BadVersion   => '1.00',
            UndefVersion => '2.00',
            BadLatest    => 'not-a-version',
            StaleVersion => '2.00',
        );
        return $versions{$module};
    }
);

subtest 'dependency analysis' => sub {
    my $dependencies = [
        {module => 'UpToDate',     version => '1.00', has_version => 1},
        {module => 'Outdated',     version => '1.00', has_version => 1},
        {module => 'NoVersion',    version => undef,  has_version => 0},
        {module => 'NotFound',     version => '1.00', has_version => 1},
        {module => 'BadVersion',   version => 'v1',   has_version => 1},
        {module => 'UndefVersion', version => undef,  has_version => 1},
        {module => 'BadLatest',    version => '1.00', has_version => 1},
        {module => 'StaleVersion', version => '1.00', has_version => 0},
    ];

    my $analyzed_dependencies = analyze_dependencies($dependencies);
    my %results_by_module =
      map { $_ -> {module} => $_ } @{$analyzed_dependencies};

    is($results_by_module{UpToDate}{is_outdated},
        0, 'Up-to-date module is not marked as outdated');
    is($results_by_module{UpToDate}{latest_version},
        '1.00', 'Up-to-date module has correct latest_version');

    is($results_by_module{Outdated}{is_outdated},
        1, 'Outdated module is marked as outdated');
    is($results_by_module{Outdated}{latest_version},
        '2.00', 'Outdated module has correct latest_version');

    is($results_by_module{NoVersion}{is_outdated},
        0, 'Module with no version is not marked as outdated');
    is($results_by_module{NoVersion}{latest_version},
        undef, 'Module with no version has undef latest_version');

    is($results_by_module{NotFound}{is_outdated},
        0, 'Module not found on CPAN is not marked as outdated');
    is($results_by_module{NotFound}{latest_version},
        undef, 'Module not found on CPAN has undef latest_version');

    is($results_by_module{BadVersion}{is_outdated},
        0, 'Module with invalid version is not marked outdated');

    is($results_by_module{UndefVersion}{is_outdated}, 0,
        'Module pinned without a parsable version is not marked as outdated');
    is($results_by_module{UndefVersion}{latest_version}, '2.00',
        'Module pinned without a parsable version still reports latest_version'
    );

    is($results_by_module{BadLatest}{is_outdated}, 0,
        'Module whose latest version is unparsable is not marked as outdated'
    );

    is($results_by_module{StaleVersion}{is_outdated}, 0,
        'Unpinned module is never marked as outdated even with a stale version field'
    );
};

subtest 'parse_version_value' => sub {
    is(scalar Bunkai::Component::Analyzer::parse_version_value(undef),
        undef, 'Returns nothing for an undefined value');
    is(
        scalar Bunkai::Component::Analyzer::parse_version_value(
            'not-a-version'),
        undef,
        'Returns nothing for an unparsable value'
    );
    is(Bunkai::Component::Analyzer::parse_version_value('1.02'),
        '1.02', 'Returns a comparable version object for a valid value');
};

done_testing();
