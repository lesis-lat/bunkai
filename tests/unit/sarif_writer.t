#!/usr/bin/env perl

package main;

use 5.034;
use strict;
use warnings;

use Const::Fast;
use English qw(-no_match_vars);
use Test::More;
use Test::Fatal;
use File::Temp qw(tempdir);
use Path::Tiny qw(path);
use JSON::PP   qw(decode_json);
use FindBin;
use lib "$FindBin::Bin/../../lib";
use lib "$FindBin::Bin/../lib";

use Bunkai::Component::SarifWriter qw(write_sarif_report);

our $VERSION = '0.0.4';

const my $FULL_DEVICE                => '/dev/full';
const my $OVERSIZED_DEPENDENCY_COUNT => 2_000;

subtest 'writes a valid SARIF document to disk' => sub {
    my $directory   = tempdir(CLEANUP => 1);
    my $output_file = path($directory) -> child('results.sarif') -> stringify;

    my $dependencies = [
        {
            module              => 'Module::Unsafe',
            has_version         => 1,
            version             => '1.00',
            is_outdated         => 0,
            has_vulnerabilities => 1,
            vulnerabilities     => [
                {
                    type          => 'vulnerability',
                    cve_id        => 'CVE-2026-0001',
                    description   => 'A sample vulnerability.',
                    fixed_version => '1.01',
                },
            ],
        },
    ];

    my $return_value =
      write_sarif_report($dependencies, '/path/to/cpanfile', $output_file);

    is($return_value, undef, 'Returns nothing on success');
    ok(-f $output_file, 'Creates the SARIF output file');

    my $decoded = decode_json(path($output_file) -> slurp);
    is($decoded -> {version}, '2.1.0', 'Serializes the SARIF version');
    is($decoded -> {runs}[0]{results}[0]{ruleId},
        'CVE-2026-0001', 'Serializes the vulnerability result rule id');
    is($decoded -> {runs}[0]{tool}{driver}{name},
        'Bunkai', 'Serializes the tool driver name');
};

subtest 'writes an empty results document for clean dependencies' => sub {
    my $directory   = tempdir(CLEANUP => 1);
    my $output_file = path($directory) -> child('empty.sarif') -> stringify;

    write_sarif_report([], '/path/to/cpanfile', $output_file);

    my $decoded = decode_json(path($output_file) -> slurp);
    is_deeply($decoded -> {runs}[0]{results},
        [], 'Writes an empty results array');
};

subtest 'croaks when the output file cannot be opened' => sub {
    my $unwritable_path =
      '/nonexistent-bunkai-directory-xyz/subdir/results.sarif';

    like(
        exception {
            write_sarif_report([], '/path/to/cpanfile', $unwritable_path)
        },
        qr{Cannot \s open \s SARIF \s output \s file}xms,
        'Croaks with an informative message when the path is invalid'
    );
};

subtest 'croaks when the output file cannot be written' => sub {
    if (!-c $FULL_DEVICE) {
        plan skip_all => "$FULL_DEVICE is not available";
    }

    my @many_dependencies = map {
        +{
            module              => "Module::Padding$_",
            version             => '1.00',
            has_version         => 1,
            latest_version      => '2.00',
            is_outdated         => 1,
            has_vulnerabilities => 0,
            vulnerabilities     => [],
        }
    } (1 .. $OVERSIZED_DEPENDENCY_COUNT);

    like(
        exception {
            write_sarif_report(\@many_dependencies, '/project/cpanfile',
                $FULL_DEVICE)
        },
        qr{Cannot \s write \s to \s SARIF \s output \s file}xms,
        'Croaks when the SARIF payload cannot be written'
    );

    like(
        exception {
            write_sarif_report([], '/project/cpanfile', $FULL_DEVICE)
        },
        qr{Cannot \s close \s SARIF \s output \s file}xms,
        'Croaks when the buffered SARIF payload cannot be flushed'
    );
};

done_testing();
