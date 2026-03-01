#!/usr/bin/env perl

package main;

use 5.034;
use strict;
use warnings;

use Test::More;
use lib '../lib/';

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
                description => q{Error: Module 'MetaCPAN::Client' is not in database},
            },
        ],
    };

    my ( $report_lines, $should_fail ) =
      generate_report_for_dependency($dependency);

    is_deeply( $report_lines, [],
        'Does not emit advisory DB miss lines in CLI report' );
    is( $should_fail, 0,
        'Does not fail dependency only due to advisory DB miss' );
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
                type => 'error',
                description =>
                  q{Error: Failed to execute cpan-audit for module 'Broken::Audit': open3 failed},
            },
        ],
    };

    my ( $report_lines, $should_fail ) =
      generate_report_for_dependency($dependency);

    is( scalar @{$report_lines}, 1,
        'Emits actionable audit execution error line' );
    like( $report_lines->[0], qr{Failed \s to \s execute \s cpan-audit}xms,
        'Report includes execution error details' );
    is( $should_fail, 1,
        'Fails dependency when audit execution has actionable error' );
};

done_testing();
