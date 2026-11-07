#!/usr/bin/env perl

package main;

use 5.034;
use strict;
use warnings;
use utf8;

use Test::More;
use Test::Fatal;
use FindBin;
use lib "$FindBin::Bin/../../lib";
use lib "$FindBin::Bin/../lib";

use Bunkai::Utils::Sarif qw(generate_sarif);

our $VERSION = '0.0.4';

use Const::Fast;
const my $RESULTS_NUMBER    => 6;
const my $ASCII_DOLLAR_SIGN => 36;
const my $SCHEMA_KEY        => chr($ASCII_DOLLAR_SIGN) . 'schema';
const my $CPANFILE_PATH     => '/path/to/project/cpanfile';
const my $RULES_NUMBER      => 4;

subtest 'Module loading and basic structure' => sub {
    plan tests => 8;

    can_ok('Bunkai::Utils::Sarif', 'generate_sarif');

    my $sarif_report = generate_sarif([], $CPANFILE_PATH);

    isa_ok($sarif_report, 'HASH', 'generate_sarif returns a hashref');
    is($sarif_report -> {version}, '2.1.0', 'SARIF report version is 2.1.0');

    ok(exists $sarif_report -> {$SCHEMA_KEY}, 'SARIF schema key exists');

    is($sarif_report -> {runs}[0]{tool}{driver}{name},
        'Bunkai', 'Tool name is correctly set to Bunkai');
    is($sarif_report -> {runs}[0]{tool}{driver}{version},
        $main::VERSION, 'Tool version is correctly set');

    my $rules = $sarif_report -> {runs}[0]{tool}{driver}{rules};
    isa_ok($rules, 'ARRAY', 'Tool rules are an array');
    is(scalar @{$rules}, 0, 'No rules for an empty dependency list');
};

subtest 'Argument validation' => sub {
    plan tests => 7;

    like(
        exception { generate_sarif(undef, $CPANFILE_PATH) },
        qr{"DependencyList" \s [(]in \s \$_\[0\][)]}xms,
        'Rejects undefined dependencies'
    );

    like(
        exception { generate_sarif({}, $CPANFILE_PATH) },
        qr{"DependencyList" \s [(]in \s \$_\[0\][)]}xms,
        'Rejects a non-arrayref for dependencies'
    );

    like(
        exception { generate_sarif([], undef) },
        qr{Must \s not \s be \s empty \s [(]in \s \$_\[1\][)]}xms,
        'Rejects an undefined cpanfile_path'
    );

    like(
        exception { generate_sarif([], q{}) },
        qr{Must \s not \s be \s empty \s [(]in \s \$_\[1\][)]}xms,
        'Rejects an empty cpanfile_path'
    );

    like(
        exception {
            generate_sarif([+{module => 'Some::Module', typo => 1}],
                $CPANFILE_PATH)
        },
        qr{type \s constraint \s "DependencyList"}xms,
        'Rejects a dependency carrying an unknown key'
    );

    like(
        exception { generate_sarif([+{version => '1.00'}], $CPANFILE_PATH) },
        qr{type \s constraint \s "DependencyList"}xms,
        'Rejects a dependency without a module name'
    );

    like(
        exception {
            generate_sarif(
                [
                    +{
                        module          => 'Some::Module',
                        vulnerabilities => +{type => 'error'},
                    },
                ],
                $CPANFILE_PATH
            );
        },
        qr{type \s constraint \s "DependencyList"}xms,
        'Rejects vulnerabilities that are not a list'
    );
};

subtest 'SARIF result generation for various dependency states' => sub {
    plan tests => 12;

    my $unpinned_dependency = {
        module              => 'Module::NoVersion',
        has_version         => 0,
        is_outdated         => 0,
        has_vulnerabilities => 0,
        vulnerabilities     => [],
    };

    my $outdated_dependency = {
        module              => 'Module::Old',
        has_version         => 1,
        version             => '1.0.0',
        is_outdated         => 1,
        latest_version      => '1.5.0',
        has_vulnerabilities => 0,
        vulnerabilities     => [],
    };

    my $vulnerable_dependency = {
        module              => 'Module::Unsafe',
        has_version         => 1,
        version             => '2.0.0',
        is_outdated         => 0,
        has_vulnerabilities => 1,
        vulnerabilities     => [
            {
                type          => 'vulnerability',
                cve_id        => 'CVE-2025-10001',
                description   => 'A sample vulnerability.',
                fixed_version => '2.0.1',
            }
        ],
    };

    my $audit_error_dependency = {
        module              => 'Module::AuditError',
        has_vulnerabilities => 1,
        vulnerabilities     =>
          [{type => 'error', description => 'Audit process failed.'}]
    };
    my $advisory_db_miss_dependency = {
        module              => 'Module::MissingAdvisory',
        has_version         => 1,
        is_outdated         => 0,
        has_vulnerabilities => 1,
        vulnerabilities     => [
            {
                type        => 'error',
                description =>
                  q{Error: Module 'Module::MissingAdvisory' is not in database}
            }
        ]
    };

    my $complex_dependency = {
        module              => 'Module::Complex',
        has_version         => 1,
        version             => '3.0.0',
        is_outdated         => 1,
        latest_version      => '3.1.0',
        has_vulnerabilities => 1,
        vulnerabilities     => [
            {
                type          => 'vulnerability',
                cve_id        => 'CPANSA-Bunkai-123',
                description   => 'Another issue.',
                fixed_version => '3.0.1',
            }
        ],
    };

    my $dependencies = [
        $unpinned_dependency,         $outdated_dependency,
        $vulnerable_dependency,       $audit_error_dependency,
        $advisory_db_miss_dependency, $complex_dependency
    ];

    my $sarif_report = generate_sarif($dependencies, $CPANFILE_PATH);
    my @results      = @{$sarif_report -> {runs}[0]{results}};
    my @rules        = @{$sarif_report -> {runs}[0]{tool}{driver}{rules}};

    is(scalar @results,
        $RESULTS_NUMBER, 'Correct total number of results generated');

    is((scalar grep { $_ -> {ruleId} eq 'BUNKAI-UNPINNED' } @results),
        2, 'Finds 2 unpinned dependency results');
    is((scalar grep { $_ -> {ruleId} eq 'BUNKAI-OUTDATED' } @results),
        2, 'Finds 2 outdated dependency results');
    is(
        (
            scalar
              grep { $_ -> {message}{text} =~ m{Module::MissingAdvisory}xms }
              @results
        ),
        0,
        'Skips advisory DB miss errors in SARIF results'
    );
    is((scalar grep { $_ -> {ruleId} eq 'CVE-2025-10001' } @results),
        1, 'Finds 1 CVE vulnerability result');
    is((scalar grep { $_ -> {ruleId} eq 'CPANSA-Bunkai-123' } @results),
        1, 'Finds 1 CPANSA vulnerability result');

    my ($vulnerability_result) =
      grep { $_ -> {ruleId} eq 'CVE-2025-10001' } @results;
    is($vulnerability_result -> {level},
        'error', 'Vulnerability level is "error"');

    my ($outdated_result) =
      grep { $_ -> {ruleId} eq 'BUNKAI-OUTDATED' } @results;
    is($outdated_result -> {level}, 'warning', 'Outdated level is "warning"');

    my ($unpinned_result) =
      grep { $_ -> {ruleId} eq 'BUNKAI-UNPINNED' } @results;
    is($unpinned_result -> {level}, 'warning', 'Unpinned level is "warning"');

    is(scalar @rules, $RULES_NUMBER, 'Expected rule definitions are present');
    my ($unpinned_rule) = grep { $_ -> {id} eq 'BUNKAI-UNPINNED' } @rules;
    is($unpinned_rule -> {properties}{tags}[0],
        'dependency', 'Unpinned rule is tagged as dependency');
    my ($vulnerability_rule) = grep { $_ -> {id} eq 'CVE-2025-10001' } @rules;
    is($vulnerability_rule -> {properties}{tags}[0],
        'security', 'Vulnerability rule is tagged as security');
};

subtest
  'Vulnerabilities without an advisory id fall back to a placeholder rule' =>
  sub {
    my $dependencies = [
        +{
            module              => 'Module::Anonymous',
            has_version         => 1,
            version             => '1.00',
            is_outdated         => 0,
            has_vulnerabilities => 1,
            vulnerabilities     => [
                +{
                    type          => 'vulnerability',
                    cve_id        => undef,
                    description   => 'Advisory without an identifier.',
                    fixed_version => undef,
                },
                +{
                    type          => 'vulnerability',
                    cve_id        => q{},
                    description   => 'Advisory with an empty identifier.',
                    fixed_version => undef,
                },
            ],
        },
    ];

    my $sarif_report = generate_sarif($dependencies, $CPANFILE_PATH);
    my @results      = @{$sarif_report -> {runs}[0]{results}};
    my @rules        = @{$sarif_report -> {runs}[0]{tool}{driver}{rules}};

    is(scalar @results, 2, 'Emits a result for each unidentified advisory');
    is((scalar grep { $_ -> {ruleId} eq 'BUNKAI-VULN-UNKNOWN' } @results),
        2, 'Both results use the placeholder rule id');
    like(
        $results[0]{message}{text},
        qr{has \s vulnerability \s BUNKAI-VULN-UNKNOWN}xms,
        'The placeholder id is rendered in the result message'
    );

    is(scalar @rules,
        1, 'Collapses both advisories into a single rule descriptor');
    is($rules[0]{id}, 'BUNKAI-VULN-UNKNOWN', 'Declares the placeholder rule');
    is($rules[0]{properties}{'security-severity'},
        '8.0', 'Vulnerability rules carry a security severity');
  };

subtest
  'SARIF results carry the full nested location and property structure' =>
  sub {
    my $dependencies = [
        +{
            module              => 'Module::NoVersion',
            has_version         => 0,
            is_outdated         => 0,
            has_vulnerabilities => 0,
            vulnerabilities     => [],
        },
        +{
            module              => 'Module::Old',
            has_version         => 1,
            version             => '1.00',
            latest_version      => '2.00',
            is_outdated         => 1,
            has_vulnerabilities => 0,
            vulnerabilities     => [],
        },
        +{
            module              => 'Module::Unsafe',
            has_version         => 1,
            version             => '1.00',
            is_outdated         => 0,
            has_vulnerabilities => 1,
            vulnerabilities     => [
                +{
                    type          => 'vulnerability',
                    cve_id        => 'CVE-2026-4242',
                    description   => 'A sample vulnerability.',
                    fixed_version => '1.50',
                },
            ],
        },
    ];

    my $sarif_report = generate_sarif($dependencies, $CPANFILE_PATH);
    my @results      = @{$sarif_report -> {runs}[0]{results}};
    my @rules        = @{$sarif_report -> {runs}[0]{tool}{driver}{rules}};

    my ($unpinned)   = grep { $_ -> {ruleId} eq 'BUNKAI-UNPINNED' } @results;
    my ($outdated)   = grep { $_ -> {ruleId} eq 'BUNKAI-OUTDATED' } @results;
    my ($vulnerable) = grep { $_ -> {ruleId} eq 'CVE-2026-4242' } @results;

    is_deeply(
        $unpinned -> {locations},
        [
            +{
                physicalLocation => +{
                    artifactLocation => +{uri => $CPANFILE_PATH},
                },
            },
        ],
        'Location is a fully nested physicalLocation/artifactLocation structure'
    );

    is_deeply(
        $unpinned -> {properties},
        +{tags => ['dependency']},
        'Unpinned results carry the dependency tag'
    );
    is_deeply(
        $outdated -> {properties},
        +{tags => ['dependency']},
        'Outdated results carry the dependency tag'
    );
    is_deeply(
        $vulnerable -> {properties},
        +{tags => ['security', 'dependency']},
        'Vulnerability results carry the security and dependency tags'
    );
    is_deeply(
        $outdated   -> {locations},
        $vulnerable -> {locations},
        'Every result points at the same cpanfile location'
    );

    my ($unpinned_rule) = grep { $_ -> {id} eq 'BUNKAI-UNPINNED' } @rules;
    is_deeply(
        $unpinned_rule -> {shortDescription},
        +{text => 'Dependency is missing a pinned version.'},
        'Rule descriptors carry a nested shortDescription'
    );

    my ($vulnerability_rule) = grep { $_ -> {id} eq 'CVE-2026-4242' } @rules;
    is_deeply(
        $vulnerability_rule -> {shortDescription},
        +{text => 'Dependency vulnerability identified.'},
        'Vulnerability rule descriptors carry a nested shortDescription'
    );
  };

done_testing();
