#!/usr/bin/env perl

package main;

use 5.034;
use strict;
use warnings;

use Test::More;
use FindBin;
use lib "$FindBin::Bin/../../lib";
use lib "$FindBin::Bin/../lib";

use Bunkai::Component::ReportGenerator qw(generate_report_for_dependency);

our $VERSION = '0.0.4';

subtest 'Suppresses advisory DB misses from report output' => sub {
    my $dependency = {
        module              => 'MetaCPAN::Client',
        has_version         => 1,
        version             => '2.039000',
        latest_version      => '2.039000',
        is_outdated         => 0,
        has_vulnerabilities => 1,
        vulnerabilities     => [
            {
                type        => 'error',
                description =>
                  q{Error: Module 'MetaCPAN::Client' is not in database},
            },
        ],
    };

    my ($report_lines, $should_fail) =
      generate_report_for_dependency($dependency);

    is_deeply($report_lines, [],
        'Does not emit advisory DB miss lines in CLI report');
    is($should_fail, 0,
        'Does not fail dependency only due to advisory DB miss');
};

subtest 'Keeps actionable audit execution errors' => sub {
    my $dependency = {
        module              => 'Broken::Audit',
        has_version         => 1,
        version             => '1.0',
        latest_version      => '1.0',
        is_outdated         => 0,
        has_vulnerabilities => 1,
        vulnerabilities     => [
            {
                type        => 'error',
                description =>
                  q{Error: Failed to execute cpan-audit for module 'Broken::Audit': open3 failed},
            },
        ],
    };

    my ($report_lines, $should_fail) =
      generate_report_for_dependency($dependency);

    is(scalar @{$report_lines},
        1, 'Emits actionable audit execution error line');
    like(
        $report_lines -> [0],
        qr{Failed \s to \s execute \s cpan-audit}xms,
        'Report includes execution error details'
    );
    is($should_fail, 1,
        'Fails dependency when audit execution has actionable error');
};

subtest 'Reports an unpinned dependency' => sub {
    my ($report_lines, $should_fail) = generate_report_for_dependency(
        +{
            module              => 'Module::NoVersion',
            has_version         => 0,
            is_outdated         => 0,
            has_vulnerabilities => 0,
            vulnerabilities     => [],
        }
    );

    is_deeply(
        $report_lines,
        [q{WARNING: Module 'Module::NoVersion' has no version specified.}],
        'Emits a single warning for a dependency without a version'
    );
    is($should_fail, 1, 'Fails the dependency when no version is pinned');
};

subtest 'Reports an outdated dependency' => sub {
    my ($report_lines, $should_fail) = generate_report_for_dependency(
        +{
            module              => 'Module::Old',
            has_version         => 1,
            version             => '1.00',
            latest_version      => '2.00',
            is_outdated         => 1,
            has_vulnerabilities => 0,
            vulnerabilities     => [],
        }
    );

    is_deeply(
        $report_lines,
        [
            q{WARNING: Module 'Module::Old' is outdated. Specified: 1.00, Latest: 2.00},
            'SUGGEST: Upgrade to version 2.00 or later.',
        ],
        'Emits a warning and an upgrade suggestion for an outdated dependency'
    );
    is($should_fail, 1, 'Fails the dependency when it is outdated');
};

subtest 'Reports an unreachable latest version' => sub {
    my ($report_lines, $should_fail) = generate_report_for_dependency(
        +{
            module              => 'Module::Unknown',
            has_version         => 1,
            version             => '1.00',
            latest_version      => undef,
            is_outdated         => 0,
            has_vulnerabilities => 0,
            vulnerabilities     => [],
        }
    );

    is_deeply(
        $report_lines,
        [q{WARNING: Could not fetch latest version for 'Module::Unknown'.}],
        'Warns when the latest version could not be fetched'
    );
    is($should_fail, 0,
        'Does not fail the dependency when only the lookup failed');
};

subtest 'Reports vulnerabilities with a remediation suggestion' => sub {
    my ($report_lines, $should_fail) = generate_report_for_dependency(
        +{
            module              => 'Module::Unsafe',
            has_version         => 1,
            version             => '1.00',
            latest_version      => '1.00',
            is_outdated         => 0,
            has_vulnerabilities => 1,
            vulnerabilities     => [
                +{
                    type          => 'vulnerability',
                    cve_id        => 'CVE-2026-1',
                    description   => 'First issue.',
                    fixed_version => undef,
                },
                +{
                    type          => 'vulnerability',
                    cve_id        => 'CVE-2026-2',
                    description   => 'Second issue.',
                    fixed_version => '1.50',
                },
                +{
                    type          => 'vulnerability',
                    cve_id        => 'CVE-2026-3',
                    description   => 'Third issue.',
                    fixed_version => '1.90',
                },
            ],
        }
    );

    is_deeply(
        $report_lines,
        [
            'SUGGEST: Upgrade to version 1.50 or later.',
            "SECURITY: Module 'Module::Unsafe' has vulnerability CVE-2026-1:\nFirst issue.",
            "SECURITY: Module 'Module::Unsafe' has vulnerability CVE-2026-2:\nSecond issue.",
            "SECURITY: Module 'Module::Unsafe' has vulnerability CVE-2026-3:\nThird issue.",
        ],
        'Emits one security line per finding and the first available fixed version'
    );
    is($should_fail, 1,
        'Fails the dependency when vulnerabilities are present');
};

subtest
  'Prefers a vulnerability fix over the latest version in suggestions' =>
  sub {
    my ($report_lines, $should_fail) = generate_report_for_dependency(
        +{
            module              => 'Module::Both',
            has_version         => 1,
            version             => '1.00',
            latest_version      => '3.00',
            is_outdated         => 1,
            has_vulnerabilities => 1,
            vulnerabilities     => [
                +{
                    type          => 'vulnerability',
                    cve_id        => 'CVE-2026-4',
                    description   => 'Fixed upstream.',
                    fixed_version => '2.00',
                },
            ],
        }
    );

    is(
        $report_lines -> [0],
        q{WARNING: Module 'Module::Both' is outdated. Specified: 1.00, Latest: 3.00},
        'Keeps the outdated warning'
    );
    is(
        $report_lines -> [1],
        'SUGGEST: Upgrade to version 2.00 or later.',
        'Suggests the vulnerability fix rather than the latest version'
    );
    is($should_fail, 1, 'Fails the dependency when outdated and vulnerable');
  };

subtest 'is_advisory_db_miss_error' => sub {
    is(
        Bunkai::Component::ReportGenerator::is_advisory_db_miss_error(undef),
        0, 'An undefined description is not an advisory DB miss'
    );
    ok(
        !Bunkai::Component::ReportGenerator::is_advisory_db_miss_error(
            'Some other error'),
        'An unrelated error is not an advisory DB miss'
    );
    ok(
        Bunkai::Component::ReportGenerator::is_advisory_db_miss_error(
            q{Error: Module 'Foo' is not in database}),
        'Recognises the advisory DB miss message'
    );
};

done_testing();
