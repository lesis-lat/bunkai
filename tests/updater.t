package main;

use 5.034;
use strict;
use warnings;

use File::Temp qw(tempdir);
use Path::Tiny qw(path);
use Test::More;

use Bunkai::Engine::Updater qw(plan_cpanfile_updates apply_cpanfile_updates);

our $VERSION = '0.0.4';

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
