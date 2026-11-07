#!/usr/bin/env perl

package main;

use 5.034;
use strict;
use warnings;

use Carp    qw(croak);
use English qw(-no_match_vars);
use POSIX   qw();
use Test::More;
use Test::MockModule;
use Const::Fast;

use FindBin;
use lib "$FindBin::Bin/../../lib";
use lib "$FindBin::Bin/../lib";

use_ok('Bunkai::Component::Auditor');

our $VERSION = '0.0.4';

const my $MOCK_PID                 => 42;
const my $EXPECTED_PARSED_FINDINGS => 3;
const my $EXPECTED_FALLBACK_IDS    => 3;

sub build_open3_mock {
    my (%arguments) = @_;

    return sub {
        open $_[0], '>', \my $stdin_buffer
          or croak "Cannot open mocked stdin: $OS_ERROR";
        open $_[1], '<', \$arguments{stdout}
          or croak "Cannot open mocked stdout: $OS_ERROR";
        open $_[2], '<', \$arguments{stderr}
          or croak "Cannot open mocked stderr: $OS_ERROR";

        if ($arguments{drain}) {
            local $INPUT_RECORD_SEPARATOR = undef;
            my $drained = (scalar readline $_[1]) // q{};
            $drained .= (scalar readline $_[2]) // q{};
            note 'Drained '
              . length($drained)
              . ' mocked bytes before the audit reads them';
        }

        if ($arguments{close_stdin}) {
            close $_[0] or croak "Cannot close mocked stdin: $OS_ERROR";
        }

        if ($arguments{orphan_pid}) {
            return $MOCK_PID;
        }

        my $child_pid = fork;
        if (!defined $child_pid) {
            croak "Cannot fork mocked cpan-audit process: $OS_ERROR";
        }
        if ($child_pid == 0) {
            POSIX::_exit(0);
        }

        return $child_pid;
    };
}
local *CORE::GLOBAL::waitpid = sub { return $MOCK_PID; };

subtest 'enrich_with_vulnerabilities' => sub {
    my $dependency   = {module => 'Some::Dependency', version => '0.50'};
    my $auditor_mock = Test::MockModule -> new('Bunkai::Component::Auditor');

    subtest 'when no vulnerabilities are found' => sub {
        $auditor_mock -> redefine(
            find_vulnerabilities_for_module => sub { return [] });
        my $result = Bunkai::Component::Auditor::enrich_with_vulnerabilities(
            $dependency);

        ok(
            !$result -> {has_vulnerabilities},
            'has_vulnerabilities flag is false'
        );
        is_deeply($result -> {vulnerabilities},
            [], 'vulnerabilities key is an empty arrayref');
        is($result -> {module},
            'Some::Dependency', 'Original dependency data is preserved');
    };

    subtest 'when vulnerabilities are found' => sub {
        my $mock_vulnerability =
          {type => 'vulnerability', cve_id => 'CVE-2024-11111'};
        $auditor_mock -> redefine(find_vulnerabilities_for_module =>
              sub { return [$mock_vulnerability] });
        my $result = Bunkai::Component::Auditor::enrich_with_vulnerabilities(
            $dependency);

        ok(
            $result -> {has_vulnerabilities},
            'has_vulnerabilities flag is true'
        );
        is_deeply($result -> {vulnerabilities},
            [$mock_vulnerability],
            'vulnerabilities key contains the correct data');
        is($result -> {version},
            '0.50', 'Original dependency data is preserved');
    };

    $auditor_mock -> unmock_all();
};

subtest 'find_vulnerabilities_for_module handles execution failures' => sub {
    my $auditor_mock = Test::MockModule -> new('Bunkai::Component::Auditor');
    my $dependency   = {
        module      => 'Broken::Audit',
        has_version => 0,
    };

    $auditor_mock -> redefine(open3 => sub { die "mocked open3 failure\n" });

    my $result = Bunkai::Component::Auditor::find_vulnerabilities_for_module(
        $dependency);

    is(scalar @{$result},
        1, 'Returns a single error item when cpan-audit execution fails');
    is($result -> [0]{type}, 'error',
        'Marks execution failure as error type');
    like(
        $result -> [0]{description},
        qr{\QError: Failed to execute cpan-audit\E}xms,
        'Includes execution failure prefix'
    );
    like($result -> [0]{description},
        qr{\Q'Broken::Audit'\E}xms,
        'Includes module name in execution failure description');
};

subtest 'parse_audit_output handles advisory DB misses as audit errors' =>
  sub {
    my $result = Bunkai::Component::Auditor::parse_audit_output(
        "Error: Module 'MetaCPAN::Client' is not in database\n");

    is(
        scalar @{$result},
        1,
        'Returns a single item when module is not present in CPAN::Audit database'
    );
    is($result -> [0]{type},
        'error', 'Marks advisory DB misses as audit errors');
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

    is(scalar @{$result},
        $EXPECTED_PARSED_FINDINGS,
        'Returns a finding for each parsed advisory/CVE id');
    ok((scalar grep { $_ -> {cve_id} eq 'CVE-2026-1111' } @{$result}) > 0,
        'Includes first CVE finding');
    ok((scalar grep { $_ -> {cve_id} eq 'CVE-2026-2222' } @{$result}) > 0,
        'Includes second CVE finding');
    ok(
        (
            scalar grep { $_ -> {cve_id} eq 'CPANSA-Example-2026-0002' }
              @{$result}
        ) > 0,
        'Falls back to CPANSA id when no CVE is present'
    );
};

subtest 'audit_dependencies (main entry point)' => sub {
    my $auditor_mock = Test::MockModule -> new('Bunkai::Component::Auditor');

    subtest 'with an empty list of dependencies' => sub {
        my $result = Bunkai::Component::Auditor::audit_dependencies([]);
        is_deeply($result, [], 'Returns an empty list for an empty input');
    };

    subtest 'with a list of dependencies' => sub {
        my $dependencies = [
            {module => 'Module::Clean', version => '1.0'},
            {module => 'Module::Vuln',  version => '2.0'},
        ];
        $auditor_mock -> redefine(
            enrich_with_vulnerabilities => sub {
                my ($dependency)   = @_;
                my $module_name    = $dependency -> {module};
                my $module_version = $dependency -> {version};
                if ($module_name eq 'Module::Vuln') {
                    return {
                        module              => $module_name,
                        version             => $module_version,
                        has_vulnerabilities => 1,
                        vulnerabilities     => [{cve_id => 'CVE-FAKE-1'}],
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
        my $result =
          Bunkai::Component::Auditor::audit_dependencies($dependencies);
        is(scalar @{$result},
            2, 'Returns a list with an item for each dependency');
        ok(
            !$result -> [0]{has_vulnerabilities},
            'First module has no vulnerabilities'
        );
        ok(
            $result -> [1]{has_vulnerabilities},
            'Second module has vulnerabilities'
        );
        is($result -> [1]{vulnerabilities}[0]{cve_id},
            'CVE-FAKE-1', 'Vulnerability details are present');
    };
};

subtest 'parse_audit_output ignores empty and clean output' => sub {
    is_deeply(Bunkai::Component::Auditor::parse_audit_output(undef),
        [], 'Undefined output yields no findings');
    is_deeply(Bunkai::Component::Auditor::parse_audit_output("  \n\t "),
        [], 'Blank output yields no findings');
    is_deeply(
        Bunkai::Component::Auditor::parse_audit_output(
            "__CPAN_AUDIT__\nNo known vulnerabilities found\n"),
        [],
        'A clean audit yields no findings'
    );
};

subtest 'parse_audit_output skips modules that only ship with perl' => sub {
    my $interpreter_output =
        "\e[31mperl (requires 1.11) has 48 advisories\e[0m\n"
      . "  \e[39;1m* CPANSA-perl-2017-12883\e[0m\n"
      . "    Affected range: <5.24.4\n";

    is_deeply(
        Bunkai::Component::Auditor::parse_audit_output($interpreter_output),
        [], 'A core only module version is not audited as a perl version');

    my $plain_output = "perl (requires 2.41) has 3 advisories\n"
      . "  * CPANSA-perl-2026-15534\n";

    is_deeply(Bunkai::Component::Auditor::parse_audit_output($plain_output),
        [], 'The interpreter is recognised without colours');

    my $distribution_output =
        "\e[31mFile-Temp (requires 0.2312) has 1 advisory\e[0m\n"
      . "  \e[39;1m* CPANSA-File-Temp-2011-4116\e[0m\n"
      . "    CVEs: CVE-2011-4116\n";

    is(
        scalar @{
            Bunkai::Component::Auditor::parse_audit_output(
                $distribution_output)
        },
        1,
        'A dual life module is still audited'
    );

    my $perl_prefixed_output =
        "perl-ldap (requires 0.68) has 1 advisory\n"
      . "  * CPANSA-perl-ldap-2020-0001\n"
      . "    CVEs: CVE-2020-0001\n";

    is(
        scalar @{
            Bunkai::Component::Auditor::parse_audit_output(
                $perl_prefixed_output)
        },
        1,
        'A distribution whose name starts with perl is still audited'
    );
};

subtest 'parse_audit_output extracts advisory metadata' => sub {
    my $output = <<'END_OUTPUT';
* CPANSA-Foo-2026-1
Fixed range: >=1.50
Affected by CVE-2026-1111 in the parser
* CPANSA-Bar-2026-2
No remediation published yet
* CPANSA-Foo-2026-1
Affected by CVE-2026-1111 in the parser
* CPANSA-Unstructured
Nothing identifiable here
END_OUTPUT

    my $findings = Bunkai::Component::Auditor::parse_audit_output($output);
    my @ids      = map { $_ -> {cve_id} } @{$findings};

    is_deeply(
        \@ids,
        ['CVE-2026-1111', 'CPANSA-Bar-2026-2', 'N/A'],
        'Emits one deduplicated finding per advisory, falling back to CPANSA and N/A ids'
    );
    like(
        $findings -> [0]{fixed_version},
        qr{\A >= \s* 1[.]50}xms,
        'Captures the fixed range of the first advisory'
    );
    is($findings -> [1]{fixed_version},
        undef, 'Leaves fixed_version undefined when no range is published');
    is($findings -> [0]{type},
        'vulnerability', 'Advisories are typed as vulnerabilities');
};

subtest 'parse_audit_output falls back to unstructured output' => sub {
    my $cve_finding = Bunkai::Component::Auditor::parse_audit_output(
        "Fixed range: >=2.00\nAffected by CVE-2026-2222 in the encoder\n");
    is(scalar @{$cve_finding},
        1, 'Unstructured output yields a single finding');
    is($cve_finding -> [0]{cve_id}, 'CVE-2026-2222',
        'Recovers a bare CVE id');
    like(
        $cve_finding -> [0]{fixed_version},
        qr{\A >= \s* 2[.]00}xms,
        'Recovers a bare fixed range'
    );

    my $cpansa_finding = Bunkai::Component::Auditor::parse_audit_output(
        'Advisory CPANSA-Baz-2026-9 applies');
    is($cpansa_finding -> [0]{cve_id},
        'CPANSA-Baz-2026-9',
        'Recovers a bare CPANSA id when no CVE is present');
    is($cpansa_finding -> [0]{fixed_version},
        undef, 'Leaves fixed_version undefined when no range is present');

    my $unknown_finding =
      Bunkai::Component::Auditor::parse_audit_output(
        'Something went sideways');
    is($unknown_finding -> [0]{cve_id},
        'N/A', 'Falls back to an N/A id for unrecognisable output');

    is(scalar @{[$cve_finding, $cpansa_finding, $unknown_finding]},
        $EXPECTED_FALLBACK_IDS, 'All three fallback shapes produce findings');
};

subtest 'find_vulnerabilities_for_module reads the audit process output' =>
  sub {
    my $auditor_mock = Test::MockModule -> new('Bunkai::Component::Auditor');
    $auditor_mock -> redefine(
        open3 => build_open3_mock(
            stdout =>
              "* CPANSA-Foo-2026-1\nAffected by CVE-2026-3333 in the parser\n",
            stderr => q{},
        )
    );

    my $findings =
      Bunkai::Component::Auditor::find_vulnerabilities_for_module(
        +{module => 'Pinned::Module', version => '1.00', has_version => 1});

    is(scalar @{$findings},
        1, 'Returns the advisory parsed from the process output');
    is($findings -> [0]{cve_id},
        'CVE-2026-3333', 'Parses the advisory id from stdout');

    $auditor_mock -> unmock_all();
  };

subtest
  'find_vulnerabilities_for_module merges stderr and tolerates empty output'
  => sub {
    my $auditor_mock = Test::MockModule -> new('Bunkai::Component::Auditor');
    $auditor_mock -> redefine(
        open3 => build_open3_mock(stdout => q{}, stderr => q{}));

    is_deeply(
        Bunkai::Component::Auditor::find_vulnerabilities_for_module(
            +{module => 'Quiet::Module', has_version => 0}
        ),
        [],
        'An audit that prints nothing yields no findings'
    );

    $auditor_mock -> redefine(
        open3 => build_open3_mock(
            stdout => q{},
            stderr => qq{Error: Module 'Quiet::Module' is not in database\n},
        )
    );

    my $findings =
      Bunkai::Component::Auditor::find_vulnerabilities_for_module(
        +{module => 'Quiet::Module', has_version => 0});
    is($findings -> [0]{type},
        'error', 'Reads advisory DB misses from stderr');

    $auditor_mock -> unmock_all();
  };

subtest
  'find_vulnerabilities_for_module warns on process handling failures' =>
  sub {
    my $auditor_mock = Test::MockModule -> new('Bunkai::Component::Auditor');
    my @warnings;
    local $SIG{__WARN__} = sub { push @warnings, $_[0]; return; };

    $auditor_mock -> redefine(
        open3 => build_open3_mock(
            stdout      => q{},
            stderr      => q{},
            close_stdin => 1,
        )
    );
    Bunkai::Component::Auditor::find_vulnerabilities_for_module(
        +{module => 'Closed::Stdin', has_version => 0});
    ok(
        (
            scalar grep { m{Could \s not \s close \s input \s handle}xms }
              @warnings
        ) > 0,
        'Warns when the input handle cannot be closed'
    );

    @warnings = ();
    $auditor_mock -> redefine(
        open3 => build_open3_mock(
            stdout     => q{},
            stderr     => q{},
            orphan_pid => 1,
        )
    );
    Bunkai::Component::Auditor::find_vulnerabilities_for_module(
        +{module => 'Orphan::Process', has_version => 0});
    ok(
        (
            scalar grep { m{Could \s not \s wait \s for \s cpan-audit}xms }
              @warnings
        ) > 0,
        'Warns when the audit process cannot be reaped'
    );

    $auditor_mock -> unmock_all();
  };

subtest
  'find_vulnerabilities_for_module tolerates handles already at end of file'
  => sub {
    my $auditor_mock = Test::MockModule -> new('Bunkai::Component::Auditor');
    $auditor_mock -> redefine(
        open3 => build_open3_mock(
            stdout => 'ignored stdout',
            stderr => 'ignored stderr',
            drain  => 1,
        )
    );

    is_deeply(
        Bunkai::Component::Auditor::find_vulnerabilities_for_module(
            +{module => 'Exhausted::Module', has_version => 0}
        ),
        [],
        'Treats exhausted output handles as empty audit output'
    );

    $auditor_mock -> unmock_all();
  };

done_testing();
