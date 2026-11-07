#!/usr/bin/env perl

package main;

use 5.034;
use strict;
use warnings;

use Carp qw(croak);
use Const::Fast;
use English qw(-no_match_vars);
use IO::Handle;
use Test::Fatal;
use Test::More;
use Test::MockModule;
use FindBin;
use lib "$FindBin::Bin/../../lib";
use lib "$FindBin::Bin/../lib";

use Bunkai::Component::AnalysisRenderer qw(render_analysis);

our $VERSION = '0.0.4';

const my $FULL_DEVICE           => '/dev/full';
const my $OVERSIZED_TEXT_LENGTH => 20_000;

sub exception_against_handle {
    my ($handle, $code, %options) = @_;

    if ($options{autoflush}) {
        $handle -> autoflush(1);
    }

    local $SIG{__WARN__} = sub { return };
    local *STDOUT = $handle;

    return exception { $code ->() };
}

sub exception_writing_to_full_device {
    my ($code, %options) = @_;

    open my $full_handle, '>', $FULL_DEVICE
      or croak "Cannot open $FULL_DEVICE: $OS_ERROR";
    my $error = exception_against_handle($full_handle, $code, %options);
    if (!close $full_handle) {
        note 'The full device refused the buffered output, as expected';
    }

    return $error;
}

sub capture_stdout {
    my ($code) = @_;
    my $buffer = q{};
    open my $capture_fh, '>', \$buffer
      or croak "Cannot open capture buffer: $OS_ERROR";
    local *STDOUT = $capture_fh;
    my $result = $code ->();
    close $capture_fh or croak "Cannot close capture buffer: $OS_ERROR";
    return ($buffer, $result);
}

my $renderer_mock =
  Test::MockModule -> new('Bunkai::Component::AnalysisRenderer');

subtest 'renders a clean dependency without issues' => sub {
    $renderer_mock -> redefine(
        generate_report_for_dependency => sub { return ([], 0) });

    my $dependencies =
      [{module => 'Clean::Module', version => '1.20', has_version => 1},];

    my ($output, $exit_code) =
      capture_stdout(sub { render_analysis($dependencies) });

    is($exit_code, 0, 'Returns a zero exit code when there are no issues');
    like($output, qr{Clean::Module}xms, 'Prints the module name');
    like($output, qr{1[.]20}xms,        'Prints the specified version');
    unlike(
        $output,
        qr{not \s specified}xms,
        'Does not label a pinned module as unspecified'
    );
};

subtest 'labels an unpinned dependency as not specified' => sub {
    $renderer_mock -> redefine(
        generate_report_for_dependency => sub { return ([], 0) });

    my $dependencies =
      [{module => 'Unpinned::Module', version => undef, has_version => 0},];

    my ($output, $exit_code) =
      capture_stdout(sub { render_analysis($dependencies) });

    is($exit_code, 0, 'Returns a zero exit code');
    like(
        $output,
        qr{Unpinned::Module \s+ not \s specified}xms,
        'Prints "not specified" when the version is missing'
    );
};

subtest 'propagates issues into the exit code and report body' => sub {
    $renderer_mock -> redefine(
        generate_report_for_dependency => sub {
            my ($dependency) = @_;
            if ($dependency -> {module} eq 'Broken::Module') {
                return (['WARNING: something is wrong'], 1);
            }
            return ([], 0);
        }
    );

    my $dependencies = [
        {module => 'Fine::Module',   version => '2.00', has_version => 1},
        {module => 'Broken::Module', version => '3.00', has_version => 1},
    ];

    my ($output, $exit_code) =
      capture_stdout(sub { render_analysis($dependencies) });

    is($exit_code, 1,
        'Returns a non-zero exit code when any dependency has issues');
    like(
        $output,
        qr{WARNING: \s something \s is \s wrong}xms,
        'Prints the report lines produced for the dependency'
    );
    like($output, qr{Fine::Module}xms,
        'Still prints dependencies without issues');
};

subtest 'renders nothing for an empty dependency list' => sub {
    my ($output, $exit_code) =
      capture_stdout(sub { render_analysis([]) });

    is($exit_code, 0,   'Returns a zero exit code for an empty list');
    is($output,    q{}, 'Produces no output for an empty list');
};

subtest 'fails loudly when STDOUT cannot be written' => sub {
    if (!-c $FULL_DEVICE) {
        plan skip_all => "$FULL_DEVICE is not available";
    }

    $renderer_mock -> unmock_all();

    my $dependency = +{
        module              => 'Noisy::Module',
        version             => '1.00',
        has_version         => 1,
        latest_version      => '1.00',
        is_outdated         => 0,
        has_vulnerabilities => 1,
        vulnerabilities     => [
            +{
                type          => 'vulnerability',
                cve_id        => 'CVE-2026-9999',
                description   => 'x' x $OVERSIZED_TEXT_LENGTH,
                fixed_version => undef,
            },
        ],
    };

    like(
        exception_writing_to_full_device(
            sub { return render_analysis([$dependency]) },
            autoflush => 1,
        ),
        qr{Cannot \s print \s dependency \s info \s to \s STDOUT}xms,
        'Croaks when the dependency header cannot be printed'
    );

    like(
        exception_writing_to_full_device(
            sub { return render_analysis([$dependency]) }
        ),
        qr{Cannot \s print \s report \s to \s STDOUT}xms,
        'Croaks when the report body cannot be printed'
    );
};

done_testing();
