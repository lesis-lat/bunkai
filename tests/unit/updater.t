package main;

use 5.034;
use strict;
use warnings;

use File::Temp qw(tempdir);
use Path::Tiny qw(path);
use Test::More;

use FindBin;
use lib "$FindBin::Bin/../../lib";
use lib "$FindBin::Bin/../lib";

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
            module              => 'Alpha',
            version             => undef,
            has_version         => 0,
            latest_version      => '1.20',
            has_vulnerabilities => 0,
            vulnerabilities     => [],
        },
        +{
            module              => 'Beta',
            version             => '1.00',
            has_version         => 1,
            latest_version      => '1.05',
            has_vulnerabilities => 1,
            vulnerabilities     => [
                +{
                    fixed_version => '>=1.02',
                },
            ],
        },
        +{
            module              => 'Gamma',
            version             => '2.00',
            has_version         => 1,
            latest_version      => '2.00',
            has_vulnerabilities => 0,
            vulnerabilities     => [],
        },
    ];

    my $updates = plan_cpanfile_updates($dependencies);

    is(scalar @{$updates},
        2, 'Plans updates for missing and vulnerable versions');
    is($updates -> [0] -> {module},
        'Alpha', 'Plans update for missing version');
    is($updates -> [0] -> {version},
        '1.20', 'Uses latest version for missing version');
    is($updates -> [1] -> {module},
        'Beta', 'Plans update for vulnerable version');
    is($updates -> [1] -> {version},
        '1.02', 'Uses fixed version for vulnerable module');
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
    ok(
        (scalar grep { $_ -> {id} eq 'missing-version-alpha' } @{$issues}) >
          0,
        'Includes deterministic issue id for missing version'
    );
    ok(
        (scalar grep { $_ -> {id} eq 'outdated-beta' } @{$issues}) > 0,
        'Includes deterministic issue id for outdated dependency'
    );
    ok(
        (
            scalar
              grep { $_ -> {id} eq 'vulnerability-fix-beta-cve-2026-12345' }
              @{$issues}
        ) > 0,
        'Includes deterministic issue id for vulnerability fix'
    );
    ok(
        (
            scalar
              grep { $_ -> {id} eq 'vulnerability-fix-beta-cve-2026-98765' }
              @{$issues}
        ) > 0,
        'Includes deterministic issue id for second vulnerability fix'
    );

    my $single = plan_single_update_by_issue_id($dependencies,
        'vulnerability-fix-beta-cve-2026-12345');
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
    my $directory = tempdir(CLEANUP => 1);
    my $cpanfile  = path($directory) -> child('cpanfile');
    $cpanfile -> spew("requires 'Alpha';\n"
          . "requires 'Beta', '1.00';\n"
          . "requires 'Gamma', '2.00';\n");

    my $updates = [
        +{module => 'Alpha', version => '1.20'},
        +{module => 'Beta',  version => '1.02'},
    ];

    my $updated = apply_cpanfile_updates($cpanfile -> stringify, $updates);
    is($updated, 2, 'Updates two dependency lines');

    my $updated_contents = $cpanfile -> slurp;
    is(
        $updated_contents,
        "requires 'Alpha', '1.20';\n"
          . "requires 'Beta', '1.02';\n"
          . "requires 'Gamma', '2.00';\n",
        'Writes updated cpanfile with new versions'
    );
};

subtest 'single issue update only changes the targeted module' => sub {
    my $dependencies = [
        +{
            module              => 'DateTime::TimeZone',
            version             => '2.66',
            has_version         => 1,
            is_outdated         => 1,
            latest_version      => '2.65',
            has_vulnerabilities => 0,
            vulnerabilities     => [],
        },
        +{
            module              => 'Nmap::Scanner',
            version             => undef,
            has_version         => 0,
            is_outdated         => 0,
            latest_version      => '1.0',
            has_vulnerabilities => 0,
            vulnerabilities     => [],
        },
        +{
            module              => 'Mojolicious',
            version             => '9.42',
            has_version         => 1,
            is_outdated         => 0,
            latest_version      => '9.42',
            has_vulnerabilities => 0,
            vulnerabilities     => [],
        },
    ];

    my $single_issue = plan_single_update_by_issue_id($dependencies,
        'missing-version-nmap-scanner');

    is_deeply(
        $single_issue,
        [
            +{
                module  => 'Nmap::Scanner',
                version => '1.0',
                reason  => 'missing_version',
            },
        ],
        'Plans a single update for the selected issue id'
    );

    my $directory = tempdir(CLEANUP => 1);
    my $cpanfile  = path($directory) -> child('cpanfile');
    $cpanfile -> spew("requires 'DateTime::TimeZone', '2.66';\n"
          . "requires 'Nmap::Scanner';\n"
          . "requires 'Mojolicious', '9.42';\n");

    my $updated =
      apply_cpanfile_updates($cpanfile -> stringify, $single_issue);
    is($updated, 1,
        'Updates exactly one dependency line for a single issue update');

    my $updated_contents = $cpanfile -> slurp;
    is(
        $updated_contents,
        "requires 'DateTime::TimeZone', '2.66';\n"
          . "requires 'Nmap::Scanner', '1.0';\n"
          . "requires 'Mojolicious', '9.42';\n",
        'Leaves unrelated dependency versions unchanged'
    );
};

subtest 'invalid issue id does not produce updates' => sub {
    my $dependencies = [
        +{
            module              => 'Example::Module',
            version             => undef,
            has_version         => 0,
            is_outdated         => 0,
            latest_version      => '1.23',
            has_vulnerabilities => 0,
            vulnerabilities     => [],
        },
    ];

    my $single_issue = plan_single_update_by_issue_id($dependencies,
        'missing-version-not-real');

    ok(!defined $single_issue, 'Returns undef for unknown issue id');
};

subtest 'version helpers tolerate malformed input' => sub {
    is(scalar Bunkai::Component::Updater::parse_version_value(undef),
        undef, 'parse_version_value returns nothing for an undefined value');
    is(
        scalar Bunkai::Component::Updater::parse_version_value(
            'not-a-version'),
        undef,
        'parse_version_value returns nothing for an unparsable value'
    );
    is(
        scalar Bunkai::Component::Updater::extract_version_from_range(undef),
        undef,
        'extract_version_from_range returns nothing for an undefined range'
    );
    is(
        scalar Bunkai::Component::Updater::extract_version_from_range(
            '>= latest'),
        undef,
        'extract_version_from_range returns nothing when the range has no digits'
    );
    is(
        Bunkai::Component::Updater::extract_version_from_range('>=1.02_01'),
        '1.02_01',
        'extract_version_from_range keeps developer release suffixes'
    );
};

subtest 'find_fixed_version scans vulnerability ranges' => sub {
    is(scalar Bunkai::Component::Updater::find_fixed_version([]),
        undef, 'Returns nothing for an empty vulnerability list');
    is(
        scalar Bunkai::Component::Updater::find_fixed_version(
            [+{fixed_version => undef}, +{fixed_version => q{}}]
        ),
        undef,
        'Skips vulnerabilities without a fixed range'
    );
    is(
        scalar Bunkai::Component::Updater::find_fixed_version(
            [+{fixed_version => 'unknown'}]
        ),
        undef,
        'Returns nothing when no range carries a version'
    );
    is(
        Bunkai::Component::Updater::find_fixed_version(
            [+{fixed_version => 'unknown'}, +{fixed_version => '>=2.10'}]
        ),
        '2.10',
        'Returns the first range that carries a version'
    );
};

subtest 'is_newer_version comparisons' => sub {
    is(Bunkai::Component::Updater::is_newer_version(undef, '1.00'),
        1, 'Any candidate is newer than a missing current version');
    is(
        Bunkai::Component::Updater::is_newer_version('not-a-version', '1.00'),
        1,
        'Unparsable current version is always replaced'
    );
    is(
        Bunkai::Component::Updater::is_newer_version('1.00', 'not-a-version'),
        1,
        'Unparsable candidate version is always accepted'
    );
    is(Bunkai::Component::Updater::is_newer_version('1.00', '1.01'),
        1, 'Higher candidate version is newer');
    is(Bunkai::Component::Updater::is_newer_version('1.00', '1.00'),
        0, 'Identical version is not newer');
    is(Bunkai::Component::Updater::is_newer_version('2.00', '1.00'),
        0, 'Lower candidate version is not newer');
};

subtest 'issue id fragments are sanitized' => sub {
    is(Bunkai::Component::Updater::sanitize_issue_fragment(undef),
        'unknown', 'Undefined fragments fall back to a placeholder');
    is(Bunkai::Component::Updater::sanitize_issue_fragment('***'),
        'unknown',
        'Fragments without alphanumerics fall back to a placeholder');
    is(Bunkai::Component::Updater::sanitize_issue_fragment('CVE-2026-1'),
        'cve-2026-1', 'Fragments are lowercased and dash separated');
    is(Bunkai::Component::Updater::sanitize_issue_fragment('0'),
        '0', 'A defined but false fragment is kept rather than replaced');
    is(
        Bunkai::Component::Updater::build_issue_id(
            'outdated', 'Foo::Bar', undef
        ),
        'outdated-foo-bar',
        'Issue ids omit an undefined advisory id'
    );
    is(
        Bunkai::Component::Updater::build_issue_id(
            'outdated', 'Foo::Bar', q{}
        ),
        'outdated-foo-bar',
        'Issue ids omit an empty advisory id'
    );
    is(
        Bunkai::Component::Updater::build_issue_id(
            'vulnerability_fix', 'Foo::Bar', 'CVE-2026-1'
        ),
        'vulnerability-fix-foo-bar-cve-2026-1',
        'Issue ids append the advisory id when present'
    );
};

subtest 'plan_issue_updates skips findings that cannot be acted on' => sub {
    my $dependencies = [
        +{
            module              => 'Audit::Error',
            version             => '1.00',
            has_version         => 1,
            is_outdated         => 0,
            latest_version      => undef,
            has_vulnerabilities => 1,
            vulnerabilities     =>
              [+{type => 'error', description => 'cpan-audit failed'},],
        },
        +{
            module              => 'No::Candidate',
            version             => '1.00',
            has_version         => 1,
            is_outdated         => 0,
            latest_version      => undef,
            has_vulnerabilities => 1,
            vulnerabilities     => [
                +{
                    type          => 'vulnerability',
                    cve_id        => 'CVE-2026-1',
                    fixed_version => undef
                },
            ],
        },
        +{
            module              => 'Already::Fixed',
            version             => '3.00',
            has_version         => 1,
            is_outdated         => 0,
            latest_version      => '3.00',
            has_vulnerabilities => 1,
            vulnerabilities     => [
                +{
                    type          => 'vulnerability',
                    cve_id        => 'CVE-2026-2',
                    fixed_version => '>=2.00'
                },
            ],
        },
        +{
            module              => 'Unpinned::Vuln',
            version             => undef,
            has_version         => 0,
            is_outdated         => 0,
            latest_version      => undef,
            has_vulnerabilities => 1,
            vulnerabilities     => [
                +{
                    type          => 'vulnerability',
                    cve_id        => 'CVE-2026-3',
                    fixed_version => '>=9.00'
                },
            ],
        },
        +{
            module              => 'Empty::Advisory',
            version             => '1.00',
            has_version         => 1,
            is_outdated         => 0,
            latest_version      => '1.00',
            has_vulnerabilities => 1,
            vulnerabilities     => [
                +{
                    type          => 'vulnerability',
                    cve_id        => q{},
                    fixed_version => '>=1.50'
                },
            ],
        },
        +{
            module              => 'Missing::Advisory',
            version             => '1.00',
            has_version         => 1,
            is_outdated         => 0,
            latest_version      => '1.00',
            has_vulnerabilities => 1,
            vulnerabilities     => [
                +{
                    type          => 'vulnerability',
                    cve_id        => undef,
                    fixed_version => '>=1.60'
                },
            ],
        },
    ];

    my $issues    = plan_issue_updates($dependencies);
    my @issue_ids = map { $_ -> {id} } @{$issues};

    is(scalar @{$issues}, 2,
        'Only actionable vulnerabilities produce issues');
    is_deeply(
        [sort @issue_ids],
        [
            'vulnerability-fix-empty-advisory-bunkai-vuln-unknown',
            'vulnerability-fix-missing-advisory-bunkai-vuln-unknown',
        ],
        'Vulnerabilities without an advisory id use a placeholder id'
    );
    is($issues -> [0]{advisory_id},
        'BUNKAI-VULN-UNKNOWN',
        'Placeholder advisory id is reported on the issue');
};

subtest 'plan_cpanfile_updates keeps the highest target per module' => sub {
    my $dependencies = [
        +{
            module              => 'Multi::Issue',
            version             => '1.00',
            has_version         => 1,
            is_outdated         => 1,
            latest_version      => '2.00',
            has_vulnerabilities => 1,
            vulnerabilities     => [
                +{
                    type          => 'vulnerability',
                    cve_id        => 'CVE-2026-7',
                    fixed_version => '>=1.50'
                },
            ],
        },
    ];

    my $issues  = plan_issue_updates($dependencies);
    my $updates = plan_cpanfile_updates($dependencies);

    is(scalar @{$issues},
        2, 'Outdated and vulnerability findings are planned separately');
    is(scalar @{$updates},
        1, 'Collapses both findings into a single cpanfile update');
    is($updates -> [0]{version},
        '2.00', 'Keeps the highest target version for the module');
};

subtest 'apply_cpanfile_updates handles no-op inputs' => sub {
    my $directory = tempdir(CLEANUP => 1);
    my $cpanfile  = path($directory) -> child('cpanfile');
    my $contents  = "requires 'Alpha';\nrequires 'Beta', '1.00';\n";
    $cpanfile -> spew($contents);

    is(apply_cpanfile_updates($cpanfile -> stringify, []),
        0, 'An empty update list is a no-op');
    is(
        apply_cpanfile_updates(
            $cpanfile -> stringify,
            [+{module => 'Omega', version => '9.99'}]
        ),
        0,
        'An update for an absent module changes nothing'
    );
    is($cpanfile -> slurp,
        $contents, 'cpanfile is left byte-identical when nothing matches');
};

subtest 'update_dependency_line supports cpanfile syntax variants' => sub {
    my $versions_by_module = +{'Foo::Bar' => '2.00', 'Baz' => '3.00'};

    my ($fat_comma_line, $fat_comma_changed) =
      Bunkai::Component::Updater::update_dependency_line(
        qq{requires "Foo::Bar" => "1.00";\n},
        $versions_by_module);
    is(
        $fat_comma_line,
        qq{requires "Foo::Bar"=> "2.00";\n},
        'Rewrites fat-comma entries and preserves the quoting style'
    );
    is($fat_comma_changed, 1, 'Reports the fat-comma line as changed');

    my ($no_newline_line, $no_newline_changed) =
      Bunkai::Component::Updater::update_dependency_line(q{requires 'Baz';},
        $versions_by_module);
    is(
        $no_newline_line,
        q{requires 'Baz', '3.00';},
        'Pins an unversioned entry on a line without a trailing newline'
    );
    is($no_newline_changed, 1, 'Reports the unversioned line as changed');

    my ($untouched_line, $untouched_changed) =
      Bunkai::Component::Updater::update_dependency_line("# just a comment\n",
        $versions_by_module);
    is(
        $untouched_line,
        "# just a comment\n",
        'Leaves non-requirement lines untouched'
    );
    is($untouched_changed, 0, 'Reports unrelated lines as unchanged');

    my ($unknown_line, $unknown_changed) =
      Bunkai::Component::Updater::update_dependency_line(
        "requires 'Unknown::Module';\n",
        $versions_by_module);
    is(
        $unknown_line,
        "requires 'Unknown::Module';\n",
        'Leaves unversioned entries alone when no update targets them'
    );
    is($unknown_changed, 0, 'Reports untargeted entries as unchanged');
};

subtest
  'plan_issue_updates falls back to the latest version and skips unreachable targets'
  => sub {
    my $dependencies = [
        +{
            module              => 'Outdated::Unknown',
            version             => '1.00',
            has_version         => 1,
            is_outdated         => 1,
            latest_version      => undef,
            has_vulnerabilities => 0,
            vulnerabilities     => [],
        },
        +{
            module              => 'Vuln::Without::Range',
            version             => '1.00',
            has_version         => 1,
            is_outdated         => 0,
            latest_version      => '4.00',
            has_vulnerabilities => 1,
            vulnerabilities     => [
                +{
                    type          => 'vulnerability',
                    cve_id        => 'CVE-2026-8',
                    fixed_version => undef
                },
            ],
        },
    ];

    my $issues      = plan_issue_updates($dependencies);
    my %issue_by_id = map { $_ -> {id} => $_ } @{$issues};

    ok(!exists $issue_by_id{'outdated-outdated-unknown'},
        'Skips an outdated dependency whose latest version is unknown');
    is(
        $issue_by_id{'vulnerability-fix-vuln-without-range-cve-2026-8'}
          {target_version},
        '4.00',
        'Falls back to the latest version when the advisory has no fixed range'
    );
  };

subtest 'plan_cpanfile_updates upgrades an already planned module' => sub {
    my $dependencies = [
        +{
            module              => 'Escalating::Module',
            version             => '1.00',
            has_version         => 1,
            is_outdated         => 1,
            latest_version      => '1.50',
            has_vulnerabilities => 1,
            vulnerabilities     => [
                +{
                    type          => 'vulnerability',
                    cve_id        => 'CVE-2026-9',
                    fixed_version => '>=2.00'
                },
            ],
        },
    ];

    my $updates = plan_cpanfile_updates($dependencies);

    is(scalar @{$updates}, 1, 'Collapses both findings into a single update');
    is($updates -> [0]{version},
        '2.00',
        'Replaces the outdated target with the higher vulnerability fix');
    is($updates -> [0]{reason},
        'vulnerability_fix', 'Keeps the reason of the winning finding');
};

done_testing;

1;
