#!/usr/bin/env perl

package main;

use 5.034;
use strict;
use warnings;

use Test::More;
use Test::MockModule;
use Const::Fast;

use lib '../lib/';

use_ok('Bunkai::Component::Auditor');

our $VERSION = '0.0.4';

const my $MOCK_PID => 42;
const my $EXPECTED_PARSED_FINDINGS => 3;
local *CORE::GLOBAL::waitpid = sub { return $MOCK_PID; };

subtest 'enrich_with_vulnerabilities' => sub {
    my $dependency = { module => 'Some::Dependency', version => '0.50' };
    my $auditor_mock = Test::MockModule -> new('Bunkai::Component::Auditor');

    subtest 'when no vulnerabilities are found' => sub {
        $auditor_mock -> redefine( find_vulnerabilities_for_module => sub { return [] } );
        my $result = Bunkai::Component::Auditor::enrich_with_vulnerabilities($dependency);

        ok( !$result -> {has_vulnerabilities}, 'has_vulnerabilities flag is false' );
        is_deeply( $result -> {vulnerabilities}, [], 'vulnerabilities key is an empty arrayref' );
        is( $result -> {module}, 'Some::Dependency', 'Original dependency data is preserved' );
    };

    subtest 'when vulnerabilities are found' => sub {
        my $mock_vulnerability = { type => 'vulnerability', cve_id => 'CVE-2024-11111' };
        $auditor_mock -> redefine( find_vulnerabilities_for_module => sub { return [$mock_vulnerability] } );
        my $result = Bunkai::Component::Auditor::enrich_with_vulnerabilities($dependency);

        ok( $result -> {has_vulnerabilities}, 'has_vulnerabilities flag is true' );
        is_deeply( $result -> {vulnerabilities}, [$mock_vulnerability], 'vulnerabilities key contains the correct data' );
        is( $result -> {version}, '0.50', 'Original dependency data is preserved' );
    };
};

subtest 'find_vulnerabilities_for_module handles execution failures' => sub {
    my $auditor_mock = Test::MockModule -> new('Bunkai::Component::Auditor');
    my $dependency = {
        module      => 'Broken::Audit',
        has_version => 0,
    };

    $auditor_mock -> redefine(
        open3 => sub { die "mocked open3 failure\n" }
    );

    my $result = Bunkai::Component::Auditor::find_vulnerabilities_for_module($dependency);

    is( scalar @{$result}, 1, 'Returns a single error item when cpan-audit execution fails' );
    is( $result -> [0]{type}, 'error', 'Marks execution failure as error type' );
    like(
        $result -> [0]{description},
        qr{\QError: Failed to execute cpan-audit\E}xms,
        'Includes execution failure prefix'
    );
    like(
        $result -> [0]{description},
        qr{\Q'Broken::Audit'\E}xms,
        'Includes module name in execution failure description'
    );
};

subtest 'parse_audit_output handles advisory DB misses as audit errors' => sub {
    my $result = Bunkai::Component::Auditor::parse_audit_output(
        "Error: Module 'MetaCPAN::Client' is not in database\n"
    );

    is( scalar @{$result}, 1, 'Returns a single item when module is not present in CPAN::Audit database' );
    is( $result -> [0]{type}, 'error', 'Marks advisory DB misses as audit errors' );
    like(
        $result -> [0]{description},
        qr{Error: \s Module \s 'MetaCPAN::Client' \s is \s not \s in \s database}xms,
        'Preserves the audit error description'
    );
};

subtest 'parse_audit_output emits one finding per advisory/CVE entry' => sub {
    my $output = <<'END_AUDIT';
Example::Module (requires 1.00) has 2 advisories
  * CPANSA-Example-2026-0001
    First advisory text.
    Fixed range:    >=1.10

    CVEs: CVE-2026-1111, CVE-2026-2222

  * CPANSA-Example-2026-0002
    Second advisory text.
    Fixed range:    >=1.20
END_AUDIT

    my $result = Bunkai::Component::Auditor::parse_audit_output($output);

    is( scalar @{$result}, $EXPECTED_PARSED_FINDINGS, 'Returns a finding for each parsed advisory/CVE id' );
    ok(
        ( scalar grep { $_ -> {cve_id} eq 'CVE-2026-1111' } @{$result} ) > 0,
        'Includes first CVE finding'
    );
    ok(
        ( scalar grep { $_ -> {cve_id} eq 'CVE-2026-2222' } @{$result} ) > 0,
        'Includes second CVE finding'
    );
    ok(
        ( scalar grep { $_ -> {cve_id} eq 'CPANSA-Example-2026-0002' } @{$result} ) > 0,
        'Falls back to CPANSA id when no CVE is present'
    );
};

subtest 'audit_dependencies (main entry point)' => sub {
    my $auditor_mock = Test::MockModule -> new('Bunkai::Component::Auditor');

    subtest 'with an empty list of dependencies' => sub {
        my $result = Bunkai::Component::Auditor::audit_dependencies( [] );
        is_deeply( $result, [], 'Returns an empty list for an empty input' );
    };

    subtest 'with a list of dependencies' => sub {
        my $dependencies = [
            { module => 'Module::Clean', version => '1.0' },
            { module => 'Module::Vuln',  version => '2.0' },
        ];
        $auditor_mock -> redefine(
            enrich_with_vulnerabilities => sub {
                my ($dependency) = @_;
                my $module_name = $dependency -> {module};
                my $module_version = $dependency -> {version};
                if ( $module_name eq 'Module::Vuln' ) {
                    return {
                        module              => $module_name,
                        version             => $module_version,
                        has_vulnerabilities => 1,
                        vulnerabilities     => [{ cve_id => 'CVE-FAKE-1' }],
                    };
                }
                return {
                    module              => $module_name,
                    version             => $module_version,
                    has_vulnerabilities => 0,
                    vulnerabilities     => [],
                };
            }
        );
        my $result = Bunkai::Component::Auditor::audit_dependencies($dependencies);
        is( scalar @{$result}, 2, 'Returns a list with an item for each dependency' );
        ok( !$result -> [0]{has_vulnerabilities}, 'First module has no vulnerabilities' );
        ok( $result -> [1]{has_vulnerabilities}, 'Second module has vulnerabilities' );
        is( $result -> [1]{vulnerabilities}[0]{cve_id}, 'CVE-FAKE-1', 'Vulnerability details are present' );
    };
};

done_testing();
