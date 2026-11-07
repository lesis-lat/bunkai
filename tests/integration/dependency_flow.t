#!/usr/bin/env perl

package main;

use 5.034;
use strict;
use warnings;

use Carp qw(croak);
use Const::Fast;
use Cwd qw(getcwd);
use IO::Handle;
use English    qw(-no_match_vars);
use File::Temp qw(tempdir);
use JSON::PP;
use Path::Tiny qw(path);
use Test::Fatal;
use Test::MockModule;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../../lib";
use lib "$FindBin::Bin/../lib";

use Bunkai::Network::DependencyFlow qw(run_flow);

our $VERSION = '0.0.4';

const my $FULL_DEVICE          => '/dev/full';
const my $PADDING_MODULE_COUNT => 400;

my %LATEST_VERSION_BY_MODULE = (
    Alpha => '2.00',
    Beta  => '1.00',
    Gamma => '3.00',
    Delta => '5.00',
);

my $analyzer_mock = Test::MockModule -> new('Bunkai::Component::Analyzer');
$analyzer_mock -> redefine(
    fetch_latest_version => sub {
        my ($module) = @_;

        if ($module =~ m{\A Padding}xms) {
            return '9.99';
        }

        return $LATEST_VERSION_BY_MODULE{$module};
    }
);

my $auditor_mock = Test::MockModule -> new('Bunkai::Component::Auditor');
$auditor_mock -> redefine(
    find_vulnerabilities_for_module => sub {
        my ($dependency) = @_;

        if ($dependency -> {module} ne 'Gamma') {
            return [];
        }

        return [
            +{
                type          => 'vulnerability',
                cve_id        => 'CVE-2026-5555',
                description   => 'Sample advisory.',
                fixed_version => '>=3.50',
            },
        ];
    }
);

sub build_project {
    my ($contents) = @_;

    my $directory = tempdir(CLEANUP => 1);
    path($directory) -> child('cpanfile') -> spew($contents);

    return $directory;
}

sub run_flow_capturing {
    my (%options) = @_;

    my $output = q{};
    open my $capture_handle, '>', \$output
      or croak "Cannot open capture handle: $OS_ERROR";

    my $result;
    {
        local *STDOUT = $capture_handle;
        $result = run_flow(%options);
    }

    close $capture_handle or croak "Cannot close capture handle: $OS_ERROR";

    return ($result, $output);
}

sub exception_against_handle {
    my ($handle, %options) = @_;

    $handle -> autoflush(1);

    local $SIG{__WARN__} = sub { return };
    local *STDOUT = $handle;

    return exception { run_flow(%options) };
}

sub exception_with_full_stdout {
    my (%options) = @_;

    open my $full_handle, '>', $FULL_DEVICE
      or croak "Cannot open $FULL_DEVICE: $OS_ERROR";
    my $error = exception_against_handle($full_handle, %options);
    if (!close $full_handle) {
        note 'The full device refused the buffered output, as expected';
    }

    return $error;
}

sub run_flow_in_project {
    my (%options) = @_;

    my $previous_directory = getcwd();
    chdir $options{project_path}
      or croak "Cannot change to '$options{project_path}': $OS_ERROR";

    my @captured = eval { run_flow_capturing(%options) };
    my $error    = $EVAL_ERROR;

    chdir $previous_directory
      or croak "Cannot change back to '$previous_directory': $OS_ERROR";

    if ($error) {
        croak $error;
    }

    return @captured;
}

subtest 'reports a missing cpanfile' => sub {
    my $directory = tempdir(CLEANUP => 1);
    my ($result) = run_flow_capturing(project_path => $directory);

    is($result -> {success},   0, 'Marks the run as unsuccessful');
    is($result -> {exit_code}, 1, 'Reports a failing exit code');
    like(
        $result -> {message},
        qr{'cpanfile' \s not \s found}xms,
        'Explains that the cpanfile is missing'
    );
};

subtest 'refuses a cpanfile that contains executable code' => sub {
    my $directory              = tempdir(CLEANUP => 1);
    my $marker                 = path($directory) -> child('executed');
    my $directory_for_cpanfile = path($directory) -> child('project');
    $directory_for_cpanfile -> mkpath;
    $directory_for_cpanfile -> child('cpanfile')
      -> spew(
        "open my \$handle, '>', '$marker';\nrequires 'Alpha', '1.00';\n");

    my ($result) =
      run_flow_capturing(
        project_path => $directory_for_cpanfile -> stringify);

    is($result -> {success},   0, 'Marks the run as unsuccessful');
    is($result -> {exit_code}, 1, 'Reports a failing exit code');
    like(
        $result -> {message},
        qr{cannot \s read .* line \s 1}xms,
        'Explains where the cpanfile could not be read'
    );
    ok(!-e $marker, 'Never executes the cpanfile');
};

subtest 'writes no reports for an unreadable cpanfile' => sub {
    my $directory  = build_project("requires \$module;\n");
    my $sarif_file = path($directory) -> child('results.sarif');
    my $plan_file  = path($directory) -> child('plan.json');

    my ($result, $output) = run_flow_capturing(
        project_path      => $directory,
        sarif_output_file => $sarif_file -> stringify,
        plan_updates_file => $plan_file  -> stringify,
        update_cpanfile   => 1,
    );

    is($result      -> {success},   0, 'Marks the run as unsuccessful');
    is($result      -> {exit_code}, 1, 'Keeps the failing exit code');
    ok(!$sarif_file -> exists, 'Writes no SARIF report');
    ok(!$plan_file  -> exists, 'Writes no updates plan');
    is(
        path($directory) -> child('cpanfile') -> slurp,
        "requires \$module;\n",
        'Leaves the cpanfile untouched'
    );
    is($output, q{}, 'Renders no analysis');
};

subtest 'reports an invalid version in the cpanfile' => sub {
    my $directory = build_project("requires 'Alpha', 'not-a-version';\n");
    my ($result) = run_flow_capturing(project_path => $directory);

    is($result -> {exit_code}, 1, 'Reports a failing exit code');
    like(
        $result -> {message},
        qr{\A Error: \s cannot \s read .* not-a-version}xms,
        'Names the invalid version'
    );
};

subtest 'analyses a project and fails on findings' => sub {
    my $directory = build_project("requires 'Alpha', '1.00';\n");
    my ($result, $output) = run_flow_capturing(project_path => $directory);

    is($result -> {success}, 1, 'Marks the run as successful');
    is($result -> {exit_code},
        1, 'Reports a failing exit code when findings exist');
    like(
        $output,
        qr{WARNING: \s Module \s 'Alpha' \s is \s outdated}xms,
        'Renders the analysis to STDOUT'
    );
};

subtest 'analyses a clean project' => sub {
    my $directory = build_project("requires 'Beta', '1.00';\n");
    my ($result, $output) = run_flow_capturing(project_path => $directory);

    is($result -> {exit_code}, 0, 'Reports a successful exit code');
    unlike($output, qr{WARNING}xms,
        'Renders no warnings for a clean project');
};

subtest 'writes an updates plan' => sub {
    my $directory = build_project("requires 'Alpha', '1.00';\n");
    my $plan_file = path($directory) -> child('plan.json');

    my ($result, $output) = run_flow_capturing(
        project_path      => $directory,
        plan_updates_file => $plan_file -> stringify,
    );

    is($result -> {exit_code},
        0, 'Forces a successful exit code when planning updates');
    like(
        $output,
        qr{Planned \s updates \s written}xms,
        'Announces the written plan'
    );

    my $plan = JSON::PP -> new -> decode($plan_file -> slurp);
    is($plan -> {project_path},
        $directory, 'Records the analysed project path');
    is($plan -> {issues}[0]{id},
        'outdated-alpha', 'Records the planned issue id');
};

subtest 'writes an updates plan to the default file name' => sub {
    my $directory = build_project("requires 'Alpha', '1.00';\n");

    my ($result) = run_flow_in_project(
        project_path      => $directory,
        plan_updates_file => q{},
    );

    is($result -> {exit_code}, 0, 'Forces a successful exit code');
    ok(path($directory) -> child('bunkai_updates.json') -> is_file,
        'Falls back to bunkai_updates.json');
};

subtest 'applies a single issue-scoped update' => sub {
    my $directory =
      build_project("requires 'Alpha', '1.00';\nrequires 'Beta', '1.00';\n");
    my $cpanfile = path($directory) -> child('cpanfile');

    my ($result, $output) = run_flow_capturing(
        project_path    => $directory,
        apply_update_id => 'outdated-alpha',
    );

    is($result -> {exit_code},
        0, 'Forces a successful exit code when applying an update');
    like(
        $output,
        qr{UPDATE: \s Alpha \s 2[.]00 \s [(]outdated-alpha[)]}xms,
        'Announces the applied update'
    );
    is(
        $cpanfile -> slurp,
        "requires 'Alpha', '2.00';\nrequires 'Beta', '1.00';\n",
        'Rewrites only the targeted dependency'
    );
};

subtest 'rejects an unknown issue id' => sub {
    my $directory = build_project("requires 'Alpha', '1.00';\n");

    my ($result) = run_flow_capturing(
        project_path    => $directory,
        apply_update_id => 'outdated-nonexistent',
    );

    is($result -> {success},   0, 'Marks the run as unsuccessful');
    is($result -> {exit_code}, 1, 'Reports a failing exit code');
    like(
        $result -> {message},
        qr{was \s not \s found}xms,
        'Explains the unknown issue id'
    );
};

subtest 'reports when an issue-scoped update rewrites nothing' => sub {
    my $directory = build_project("requires('Delta', '1.00');\n");

    my (undef, $output) = run_flow_capturing(
        project_path    => $directory,
        apply_update_id => 'outdated-delta',
    );

    like(
        $output,
        qr{No \s cpanfile \s updates \s required \s for \s issue}xms,
        'Announces that no cpanfile line matched'
    );
};

subtest 'applies every planned update in bulk' => sub {
    my $directory =
      build_project("requires 'Alpha', '1.00';\nrequires 'Gamma', '3.00';\n");
    my $cpanfile = path($directory) -> child('cpanfile');

    my ($result, $output) = run_flow_capturing(
        project_path    => $directory,
        update_cpanfile => 1,
    );

    is($result -> {exit_code},
        0, 'Forces a successful exit code when updating in bulk');
    like(
        $output,
        qr{Updated \s cpanfile \s entries: \s 2}xms,
        'Reports the number of rewrites'
    );
    is(
        $cpanfile -> slurp,
        "requires 'Alpha', '2.00';\nrequires 'Gamma', '3.50';\n",
        'Applies both the outdated and the vulnerability fix'
    );
};

subtest 'reports when a bulk update has nothing to do' => sub {
    my $directory = build_project("requires 'Beta', '1.00';\n");

    my (undef, $output) = run_flow_capturing(
        project_path    => $directory,
        update_cpanfile => 1,
    );

    like(
        $output,
        qr{No \s cpanfile \s updates \s required[.]}xms,
        'Announces that the cpanfile is already current'
    );
};

subtest 'writes a SARIF report' => sub {
    my $directory  = build_project("requires 'Gamma', '3.00';\n");
    my $sarif_file = path($directory) -> child('results.sarif');

    my ($result) = run_flow_capturing(
        project_path      => $directory,
        sarif_output_file => $sarif_file -> stringify,
    );

    is($result -> {exit_code},
        1, 'Keeps the failing exit code for an advisory when writing SARIF');

    my $document = JSON::PP -> new -> decode($sarif_file -> slurp);
    is($document -> {runs}[0]{results}[0]{ruleId},
        'CVE-2026-5555', 'Reports the vulnerability in the SARIF document');
};

subtest 'writes a SARIF report to the default file name' => sub {
    my $directory = build_project("requires 'Gamma', '3.00';\n");

    my ($result) = run_flow_in_project(
        project_path      => $directory,
        sarif_output_file => q{},
    );

    is($result -> {exit_code}, 1, 'Keeps the failing exit code');
    ok(path($directory) -> child('bunkai_results.sarif') -> is_file,
        'Falls back to bunkai_results.sarif');
};

subtest 'fails a SARIF scan with an outdated dependency' => sub {
    my $directory  = build_project("requires 'Alpha', '1.00';\n");
    my $sarif_file = path($directory) -> child('results.sarif');

    my ($result, $output) = run_flow_capturing(
        project_path      => $directory,
        sarif_output_file => $sarif_file -> stringify,
    );

    is($result     -> {exit_code}, 1, 'Reports a failing exit code');
    ok($sarif_file -> is_file, 'Still writes the SARIF report');
    like(
        $output,
        qr{WARNING: \s Module \s 'Alpha' \s is \s outdated}xms,
        'Still renders the finding'
    );
};

subtest 'fails a SARIF scan with an unversioned dependency' => sub {
    my $directory  = build_project("requires 'Beta';\n");
    my $sarif_file = path($directory) -> child('results.sarif');

    my ($result) = run_flow_capturing(
        project_path      => $directory,
        sarif_output_file => $sarif_file -> stringify,
    );

    is($result -> {exit_code}, 1, 'Reports a failing exit code');
    my $document = JSON::PP -> new -> decode($sarif_file -> slurp);
    is($document -> {runs}[0]{results}[0]{ruleId},
        'BUNKAI-UNPINNED', 'Reports the unpinned dependency in SARIF');
};

subtest 'passes a clean SARIF scan' => sub {
    my $directory  = build_project("requires 'Beta', '1.00';\n");
    my $sarif_file = path($directory) -> child('results.sarif');

    my ($result) = run_flow_capturing(
        project_path      => $directory,
        sarif_output_file => $sarif_file -> stringify,
    );

    is($result -> {exit_code}, 0, 'Reports a successful exit code');
    my $document = JSON::PP -> new -> decode($sarif_file -> slurp);
    is_deeply($document -> {runs}[0]{results},
        [], 'Writes a SARIF report without results');
};

subtest 'gives the same verdict with and without SARIF' => sub {
    foreach my $cpanfile (
        "requires 'Alpha', '1.00';\n",
        "requires 'Beta';\n",
        "requires 'Gamma', '3.00';\n",
        "requires 'Beta', '1.00';\n",
      )
    {
        my $directory      = build_project($cpanfile);
        my ($plain_result) = run_flow_capturing(project_path => $directory);
        my ($sarif_result) = run_flow_capturing(
            project_path      => $directory,
            sarif_output_file =>
              path($directory) -> child('results.sarif') -> stringify,
        );

        is(
            $sarif_result -> {exit_code},
            $plain_result -> {exit_code},
            "Matches the plain scan for $cpanfile"
        );
    }
};

subtest 'fails a SARIF scan without a cpanfile' => sub {
    my $directory  = tempdir(CLEANUP => 1);
    my $sarif_file = path($directory) -> child('results.sarif');

    my ($result) = run_flow_capturing(
        project_path      => $directory,
        sarif_output_file => $sarif_file -> stringify,
    );

    is($result      -> {exit_code}, 1, 'Reports a failing exit code');
    ok(!$sarif_file -> exists, 'Writes no SARIF report');
};

subtest 'fails loudly when the SARIF report cannot be written' => sub {
    my $directory = build_project("requires 'Beta', '1.00';\n");

    ok(
        exception {
            run_flow_capturing(
                project_path      => $directory,
                sarif_output_file => path($directory)
                  -> child('missing')
                  -> child('results.sarif')
                  -> stringify,
            );
        },
        'Raises an error for an unwritable SARIF path'
    );
};

subtest 'keeps forcing success for update operations combined with SARIF' =>
  sub {
    my $directory = build_project("requires 'Alpha', '1.00';\n");

    my ($result) = run_flow_capturing(
        project_path      => $directory,
        sarif_output_file =>
          path($directory) -> child('results.sarif') -> stringify,
        plan_updates_file =>
          path($directory) -> child('plan.json') -> stringify,
    );

    is($result -> {exit_code}, 0,
        'Planning updates still exits successfully');
  };

subtest 'treats an empty issue id as no issue-scoped update' => sub {
    my $directory = build_project("requires 'Alpha', '1.00';\n");
    my $cpanfile  = path($directory) -> child('cpanfile');

    my ($result) = run_flow_capturing(
        project_path    => $directory,
        apply_update_id => q{},
    );

    is($result -> {success},
        1, 'Reports the run as successful rather than an unknown issue id');
    is($result -> {message},
        undef, 'Does not report an error message for an empty issue id');
    is($result -> {exit_code}, 1, 'Does not force a successful exit code');
    is(
        $cpanfile -> slurp,
        "requires 'Alpha', '1.00';\n",
        'Leaves the cpanfile untouched'
    );
};

subtest 'fails loudly when the updates plan cannot be written' => sub {
    my $directory = build_project("requires 'Alpha', '1.00';\n");

    like(
        exception {
            run_flow(
                project_path      => $directory,
                plan_updates_file => path($directory)
                  -> child('missing')
                  -> child('plan.json')
                  -> stringify,
            );
        },
        qr{Cannot \s open \s updates \s plan \s file}xms,
        'Croaks when the plan file cannot be created'
    );
};

subtest 'fails loudly when the updates plan cannot be flushed' => sub {
    if (!-c $FULL_DEVICE) {
        plan skip_all => "$FULL_DEVICE is not available";
    }

    my $directory = build_project("requires 'Alpha', '1.00';\n");

    like(
        exception {
            run_flow(
                project_path      => $directory,
                plan_updates_file => $FULL_DEVICE,
            );
        },
        qr{Cannot \s close \s updates \s plan \s file}xms,
        'Croaks when the buffered plan cannot be flushed'
    );

    my $padding = join q{},
      map { "requires 'Padding$_', '1.00';\n" } (1 .. $PADDING_MODULE_COUNT);
    my $large_directory = build_project($padding);

    like(
        exception {
            run_flow(
                project_path      => $large_directory,
                plan_updates_file => $FULL_DEVICE,
            );
        },
        qr{Cannot \s write \s updates \s plan \s file}xms,
        'Croaks when a large plan cannot be written'
    );
};

subtest 'fails loudly when progress cannot be printed' => sub {
    if (!-c $FULL_DEVICE) {
        plan skip_all => "$FULL_DEVICE is not available";
    }

    my $outdated_project = build_project("requires 'Alpha', '1.00';\n");
    like(
        exception_with_full_stdout(
            project_path      => $outdated_project,
            plan_updates_file =>
              path($outdated_project) -> child('plan.json') -> stringify,
        ),
        qr{Cannot \s print \s plan \s summary \s to \s STDOUT}xms,
        'Croaks when the plan summary cannot be printed'
    );

    like(
        exception_with_full_stdout(
            project_path    => build_project("requires 'Alpha', '1.00';\n"),
            apply_update_id => 'outdated-alpha',
        ),
        qr{Cannot \s print \s update \s info \s to \s STDOUT}xms,
        'Croaks when a single applied update cannot be printed'
    );

    like(
        exception_with_full_stdout(
            project_path    => build_project("requires('Delta', '1.00');\n"),
            apply_update_id => 'outdated-delta',
        ),
        qr{Cannot \s print \s update \s summary \s to \s STDOUT}xms,
        'Croaks when the no-op single update summary cannot be printed'
    );

    like(
        exception_with_full_stdout(
            project_path    => build_project("requires 'Alpha', '1.00';\n"),
            update_cpanfile => 1,
        ),
        qr{Cannot \s print \s update \s info \s to \s STDOUT}xms,
        'Croaks when a bulk update cannot be printed'
    );

    like(
        exception_with_full_stdout(
            project_path    => build_project("requires 'Beta', '1.00';\n"),
            update_cpanfile => 1,
        ),
        qr{Cannot \s print \s update \s summary \s to \s STDOUT}xms,
        'Croaks when the empty bulk update summary cannot be printed'
    );
};

done_testing();
