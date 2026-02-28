package main;

use 5.034;
use strict;
use warnings;

use File::Temp qw(tempdir);
use Path::Tiny qw(path);
use Test::More;

use Bunkai::Component::Updater qw(
  plan_issue_updates
  plan_single_update_by_issue_id
  plan_cpanfile_updates
  apply_cpanfile_updates
);
use Const::Fast;

our $VERSION = '0.0.4';
const my $EXPECTED_ISSUE_COUNT => 4;

subtest 'plan_cpanfile_updates' => sub {
    my $dependencies = [
        +{
            module          => 'Alpha',
            version         => undef,
            has_version     => 0,
            latest_version  => '1.20',
            has_vulnerabilities => 0,
            vulnerabilities => [],
        },
        +{
            module          => 'Beta',
            version         => '1.00',
            has_version     => 1,
            latest_version  => '1.05',
            has_vulnerabilities => 1,
            vulnerabilities => [
                +{
                    fixed_version => '>=1.02',
                },
            ],
        },
        +{
            module          => 'Gamma',
            version         => '2.00',
            has_version     => 1,
            latest_version  => '2.00',
            has_vulnerabilities => 0,
            vulnerabilities => [],
        },
    ];

    my $updates = plan_cpanfile_updates($dependencies);

    is( scalar @{$updates}, 2, 'Plans updates for missing and vulnerable versions' );
    is( $updates -> [0] -> {module}, 'Alpha', 'Plans update for missing version' );
    is( $updates -> [0] -> {version}, '1.20', 'Uses latest version for missing version' );
    is( $updates -> [1] -> {module}, 'Beta', 'Plans update for vulnerable version' );
    is( $updates -> [1] -> {version}, '1.02', 'Uses fixed version for vulnerable module' );
};

subtest 'plan_issue_updates and single-issue selection' => sub {
    my $dependencies = [
        +{
            module              => 'Alpha',
            version             => undef,
            has_version         => 0,
            is_outdated         => 0,
            latest_version      => '1.20',
            has_vulnerabilities => 0,
            vulnerabilities     => [],
        },
        +{
            module              => 'Beta',
            version             => '1.00',
            has_version         => 1,
            is_outdated         => 1,
            latest_version      => '1.05',
            has_vulnerabilities => 1,
            vulnerabilities     => [
                +{
                    type          => 'vulnerability',
                    cve_id        => 'CVE-2026-12345',
                    fixed_version => '>=1.02',
                },
                +{
                    type          => 'vulnerability',
                    cve_id        => 'CVE-2026-98765',
                    fixed_version => '>=1.03',
                },
            ],
        },
    ];

    my $issues = plan_issue_updates($dependencies);

    is(
        scalar @{$issues},
        $EXPECTED_ISSUE_COUNT,
        'Plans issue-scoped updates for missing, outdated, and each vulnerability finding'
    );
    ok( ( scalar grep { $_ -> {id} eq 'missing-version-alpha' } @{$issues} ) > 0,
        'Includes deterministic issue id for missing version' );
    ok( ( scalar grep { $_ -> {id} eq 'outdated-beta' } @{$issues} ) > 0,
        'Includes deterministic issue id for outdated dependency' );
    ok( ( scalar grep { $_ -> {id} eq 'vulnerability-fix-beta-cve-2026-12345' } @{$issues} ) > 0,
        'Includes deterministic issue id for vulnerability fix' );
    ok( ( scalar grep { $_ -> {id} eq 'vulnerability-fix-beta-cve-2026-98765' } @{$issues} ) > 0,
        'Includes deterministic issue id for second vulnerability fix' );

    my $single = plan_single_update_by_issue_id( $dependencies, 'vulnerability-fix-beta-cve-2026-12345' );
    is_deeply(
        $single,
        [
            +{
                module  => 'Beta',
                version => '1.02',
                reason  => 'vulnerability_fix',
            },
        ],
        'Selects a single cpanfile update entry for a specific issue id'
    );
};

subtest 'apply_cpanfile_updates' => sub {
    my $directory = tempdir( CLEANUP => 1 );
    my $cpanfile = path($directory) -> child('cpanfile');
    $cpanfile -> spew(
        "requires 'Alpha';\n"
        . "requires 'Beta', '1.00';\n"
        . "requires 'Gamma', '2.00';\n"
    );

    my $updates = [
        +{ module => 'Alpha', version => '1.20' },
        +{ module => 'Beta',  version => '1.02' },
    ];

    my $updated = apply_cpanfile_updates( $cpanfile -> stringify, $updates );
    is( $updated, 2, 'Updates two dependency lines' );

    my $updated_contents = $cpanfile -> slurp;
    is(
        $updated_contents,
        "requires 'Alpha', '1.20';\n"
        . "requires 'Beta', '1.02';\n"
        . "requires 'Gamma', '2.00';\n",
        'Writes updated cpanfile with new versions'
    );
};

done_testing;

1;
