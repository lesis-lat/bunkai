#!/usr/bin/env perl

use 5.034;
use strict;
use warnings;

use Test::More;
use Test::MockModule;
use Const::Fast;

use lib '../lib/';

use_ok('Bunkai::Engine::Auditor');

our $VERSION = '0.0.3';

const my $MOCK_PID => 42;
local *CORE::GLOBAL::waitpid = sub { return $MOCK_PID; };

subtest 'enrich_with_vulnerabilities' => sub {
    my $dependency = { module => 'Some::Dependency', version => '0.50' };
    my $auditor_mock = Test::MockModule->new('Bunkai::Engine::Auditor');

    subtest 'when no vulnerabilities are found' => sub {
        $auditor_mock->redefine( find_vulnerabilities_for_module => sub { return [] } );
        my $result = Bunkai::Engine::Auditor::enrich_with_vulnerabilities($dependency);

        ok( !$result->{has_vulnerabilities}, 'has_vulnerabilities flag is false' );
        is_deeply( $result->{vulnerabilities}, [], 'vulnerabilities key is an empty arrayref' );
        is( $result->{module}, 'Some::Dependency', 'Original dependency data is preserved' );
    };

    subtest 'when vulnerabilities are found' => sub {
        my $mock_vuln = { type => 'vulnerability', cve_id => 'CVE-2024-11111' };
        $auditor_mock->redefine( find_vulnerabilities_for_module => sub { return [$mock_vuln] } );
        my $result = Bunkai::Engine::Auditor::enrich_with_vulnerabilities($dependency);

        ok( $result->{has_vulnerabilities}, 'has_vulnerabilities flag is true' );
        is_deeply( $result->{vulnerabilities}, [$mock_vuln], 'vulnerabilities key contains the correct data' );
        is( $result->{version}, '0.50', 'Original dependency data is preserved' );
    };
};

subtest 'audit_dependencies (main entry point)' => sub {
    my $auditor_mock = Test::MockModule->new('Bunkai::Engine::Auditor');

    subtest 'with an empty list of dependencies' => sub {
        my $result = Bunkai::Engine::Auditor::audit_dependencies( [] );
        is_deeply( $result, [], 'Returns an empty list for an empty input' );
    };

    subtest 'with a list of dependencies' => sub {
        my $dependencies = [
            { module => 'Module::Clean', version => '1.0' },
            { module => 'Module::Vuln',  version => '2.0' },
        ];
        $auditor_mock->redefine(
            enrich_with_vulnerabilities => sub {
                my ($dep) = @_;
                if ( $dep->{module} eq 'Module::Vuln' ) {
                    return { $dep->%*, has_vulnerabilities => 1, vulnerabilities => [{ cve_id => 'CVE-FAKE-1' }] };
                }
                return { $dep->%*, has_vulnerabilities => 0, vulnerabilities => [] };
            }
        );
        my $result = Bunkai::Engine::Auditor::audit_dependencies($dependencies);
        is( scalar $result->@*, 2, 'Returns a list with an item for each dependency' );
        ok( !$result->[0]{has_vulnerabilities}, 'First module has no vulnerabilities' );
        ok( $result->[1]{has_vulnerabilities}, 'Second module has vulnerabilities' );
        is( $result->[1]{vulnerabilities}[0]{cve_id}, 'CVE-FAKE-1', 'Vulnerability details are present' );
    };
};

done_testing();
