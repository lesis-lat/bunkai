#!/usr/bin/env perl

package main;

use 5.034;
use strict;
use warnings;

use Test::More;
use FindBin;
use lib "$FindBin::Bin/../../lib";
use lib "$FindBin::Bin/../lib";

use Bunkai::Types qw(
  CpanfileUpdate
  Dependency
  DependencyList
  IssueReason
  ModuleName
  ParserResult
  PlannedIssue
  Vulnerability
  VersionValue
);

our $VERSION = '0.0.4';

subtest 'ModuleName' => sub {
    ok(ModuleName  -> check('Try::Tiny'), 'Accepts a module name');
    ok(!ModuleName -> check(q{}),         'Rejects an empty name');
    ok(!ModuleName -> check(undef),       'Rejects an undefined name');
    ok(!ModuleName -> check([]),          'Rejects a reference');
};

subtest 'VersionValue' => sub {
    ok(VersionValue  -> check('1.02'), 'Accepts a version string');
    ok(VersionValue  -> check(undef),  'Accepts an unpinned version');
    ok(!VersionValue -> check([]),     'Rejects a reference');
};

subtest 'Vulnerability' => sub {
    ok(
        Vulnerability -> check(
            +{
                type          => 'vulnerability',
                cve_id        => 'CVE-2026-1',
                description   => 'Something.',
                fixed_version => '>=1.50',
            }
        ),
        'Accepts a complete advisory'
    );
    ok(
        Vulnerability -> check(
            +{type => 'error', description => 'Audit failed.'}),
        'Accepts an audit error record'
    );
    ok(Vulnerability  -> check(+{}), 'Accepts an empty record');
    ok(!Vulnerability -> check(+{type => 'warning'}),
        'Rejects an unknown type');
    ok(!Vulnerability -> check(+{surprise => 1}), 'Rejects an unknown key');
    ok(!Vulnerability -> check([]),               'Rejects a non-hash');
};

subtest 'Dependency' => sub {
    ok(Dependency -> check(+{module => 'Try::Tiny'}),
        'Accepts a bare module entry');
    ok(
        Dependency -> check(
            +{
                module              => 'Try::Tiny',
                version             => '0.30',
                has_version         => 1,
                latest_version      => '0.32',
                is_outdated         => 1,
                vulnerabilities     => [],
                has_vulnerabilities => 0,
            }
        ),
        'Accepts a fully audited dependency'
    );
    ok(
        !Dependency -> check(+{version => '1.00'}),
        'Rejects an entry without a module'
    );
    ok(!Dependency -> check(+{module => 'A', typo => 1}),
        'Rejects an unknown key');
    ok(!Dependency -> check(+{module => 'A', vulnerabilities => +{}}),
        'Rejects vulnerabilities that are not a list');
    ok(
        !Dependency -> check(
            +{module => 'A', vulnerabilities => [+{type => 'nope'}]}),
        'Rejects a malformed nested advisory'
    );
};

subtest 'DependencyList' => sub {
    ok(DependencyList -> check([]), 'Accepts an empty list');
    ok(DependencyList -> check([+{module => 'A'}]),
        'Accepts a list of dependencies');
    ok(!DependencyList -> check(+{module => 'A'}),
        'Rejects a bare dependency');
    ok(!DependencyList -> check([+{}]),
        'Rejects a list holding a malformed entry');
};

subtest 'IssueReason and PlannedIssue' => sub {
    ok(IssueReason  -> check('outdated'), 'Accepts a known reason');
    ok(!IssueReason -> check('refactor'), 'Rejects an unknown reason');

    my $issue = +{
        id              => 'outdated-try-tiny',
        module          => 'Try::Tiny',
        current_version => '0.30',
        target_version  => '0.32',
        reason          => 'outdated',
        advisory_id     => undef,
    };
    ok(PlannedIssue -> check($issue), 'Accepts a planned issue');

    ok(
        !PlannedIssue -> check(+{%{$issue}, reason => 'refactor'}),
        'Rejects a planned issue with an unknown reason'
    );
    ok(
        !PlannedIssue -> check(+{%{$issue}, target_version => undef}),
        'Rejects a planned issue without a target version'
    );

    my %partial = %{$issue};
    delete $partial{advisory_id};
    ok(
        !PlannedIssue -> check(\%partial),
        'Rejects a planned issue missing a key'
    );
};

subtest 'CpanfileUpdate' => sub {
    ok(
        CpanfileUpdate -> check(+{module => 'Try::Tiny', version => '0.32'}),
        'Accepts an update without a reason'
    );
    ok(
        CpanfileUpdate -> check(
            +{
                module  => 'Try::Tiny',
                version => '0.32',
                reason  => 'vulnerability_fix'
            }
        ),
        'Accepts an update carrying a reason'
    );
    ok(
        !CpanfileUpdate -> check(+{module => 'Try::Tiny'}),
        'Rejects an update without a target version'
    );
};

subtest 'ParserResult' => sub {
    ok(
        ParserResult -> check(
            +{success => 1, data => [], cpanfile_path => '/p/cpanfile'}),
        'Accepts a successful parse result'
    );
    ok(
        ParserResult -> check(
            +{
                success       => 0,
                reason        => 'cpanfile_not_found',
                data          => [],
                cpanfile_path => '/p/cpanfile',
            }
        ),
        'Accepts a failed parse result'
    );
    ok(
        !ParserResult -> check(
            +{success => 1, cpanfile_path => '/p/cpanfile'}),
        'Rejects a parse result without data'
    );
};

done_testing();
