#!/usr/bin/env perl

use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../lib";
use lib "$FindBin::Bin/../lib";

use English qw(-no_match_vars);
use File::Spec;
use JSON::PP qw(decode_json);
use Readonly;
use Test::More;

use Bunkai::Test::Directory;

our $VERSION = '0.0.4';

Readonly my $EXIT_STATUS_SHIFT => 8;
Readonly my $SARIF_VERSION     => '2.1.0';

my $repository = File::Spec -> catdir($FindBin::Bin, q{..}, q{..});

sub run_bunkai {
    my (@arguments) = @_;

    my $command = join q{ },
      map { quotemeta } ($EXECUTABLE_NAME, '-Ilib', 'bunkai.pl', @arguments);

    my $output = qx{cd @{[quotemeta $repository]} && $command 2>&1};    ## no critic (InputOutput::ProhibitBacktickOperators)

    return {
        output => $output,
        status => $CHILD_ERROR >> $EXIT_STATUS_SHIFT,
    };
}

sub project_with {
    my ($body) = @_;

    my $directory = Bunkai::Test::Directory -> new();
    my $cpanfile  = File::Spec -> catfile($directory, 'cpanfile');

    open my $handle, '>', $cpanfile
      or die "cannot write $cpanfile: $ERRNO\n";
    print {$handle} $body or die "cannot fill $cpanfile: $ERRNO\n";
    close $handle         or die "cannot close $cpanfile: $ERRNO\n";

    return $directory;
}

sub read_json {
    my ($path) = @_;

    open my $handle, '<', $path or die "cannot read $path: $ERRNO\n";
    my $content = do { local $INPUT_RECORD_SEPARATOR = undef; <$handle> };
    close $handle or die "cannot close $path: $ERRNO\n";

    return decode_json($content);
}

plan tests => 9;

subtest 'the banner documents the interface' => sub {
    plan tests => 4;

    my $result = run_bunkai();

    like($result -> {output},
        qr/--path\sis\srequired/xms, 'the missing path is explained');
    like(
        $result -> {output},
        qr/Bunkai\sv\d+[.]\d+[.]\d+/xms,
        'the banner carries the version'
    );
    like($result -> {output}, qr/--sarif/xms, 'the sarif option is named');
    like(
        $result -> {output},
        qr/--update-cpanfile/xms,
        'the update option is named'
    );
};

subtest 'a directory without a cpanfile is refused' => sub {
    plan tests => 1;

    my $empty  = Bunkai::Test::Directory -> new();
    my $result = run_bunkai('--path', $empty);

    like($result -> {output},
        qr/cpanfile/ixms, 'the missing cpanfile is named');
};

subtest 'a cpanfile with code is refused without running it' => sub {
    plan tests => 3;

    my $markers = Bunkai::Test::Directory -> new();
    my $marker  = File::Spec              -> catfile($markers, 'executed');
    my $project = project_with(
        "open my \$handle, '>', '$marker';\nrequires 'Try::Tiny';\n");
    my $result = run_bunkai('--path', $project);

    is($result -> {status}, 1, 'the scan fails');
    like(
        $result -> {output},
        qr/cannot\sread.*line\s1:\sunsupported\scharacter/xms,
        'the offending line is named'
    );
    ok(!-e $marker, 'the cpanfile is never executed');
};

subtest 'the short path option is accepted' => sub {
    plan tests => 3;

    my $project = project_with("requires 'Try::Tiny';\n");
    my $result  = run_bunkai('-p', $project);

    is($result     -> {status}, 1, 'the scan runs and the gate closes');
    like($result   -> {output}, qr/Try::Tiny/xms, 'the project is scanned');
    unlike($result -> {output},
        qr/--path\sis\srequired/xms,
        'the option is not mistaken for a missing path');
};

subtest 'the short path option still validates the directory' => sub {
    plan tests => 2;

    my $missing =
      File::Spec -> catdir(Bunkai::Test::Directory -> new(), 'missing');
    my $result = run_bunkai('-p', $missing);

    is($result -> {status}, 1, 'the run fails');
    like(
        $result -> {output},
        qr/--path\sis\srequired\sand\smust\sbe\sa\svalid\sdirectory/xms,
        'the invalid directory is explained'
    );
};

subtest 'a dependency without a version is reported' => sub {
    plan tests => 3;

    my $project = project_with("requires 'Try::Tiny';\n");
    my $result  = run_bunkai('--path', $project);

    is($result   -> {status}, 1, 'the gate closes on a finding');
    like($result -> {output}, qr/Try::Tiny/xms, 'the module is named');
    like(
        $result -> {output},
        qr/has\sno\sversion\sspecified/xms,
        'the missing version is explained'
    );
};

subtest 'a pinned dependency is read back from the cpanfile' => sub {
    plan tests => 2;

    my $project = project_with("requires 'Try::Tiny', '== 0.31';\n");
    my $result  = run_bunkai('--path', $project);

    is($result -> {status}, 1, 'an outdated pin closes the gate');
    like(
        $result -> {output},
        qr/Try::Tiny \s+ 0[.]31/xms,
        'the pinned version is echoed back'
    );
};

subtest 'the sarif report is well formed' => sub {
    plan tests => 6;

    my $project = project_with("requires 'Try::Tiny';\n");
    my $report  = File::Spec -> catfile($project, 'result.sarif');
    my $result  = run_bunkai('--path', $project, "--sarif=$report");

    is($result -> {status},
        1, 'writing a report keeps the failing exit for findings');
    ok(-f $report, 'the report file is created');

    my $document = read_json($report);

    is($document -> {version},
        $SARIF_VERSION, 'the report declares the sarif version');

    my $run = $document -> {runs}[0];

    is($run -> {tool}{driver}{name}, 'Bunkai', 'the driver is named');
    cmp_ok(scalar @{$run -> {results}},
        '>', 0, 'the finding reaches the report');

    my $without_report = run_bunkai('--path', $project);

    is($without_report -> {status},
        1, 'the same project still closes the gate without a report');
};

subtest 'a clean project passes while writing a sarif report' => sub {
    plan tests => 3;

    my $project = project_with(q{});
    my $report  = File::Spec -> catfile($project, 'result.sarif');
    my $result  = run_bunkai('--path', $project, "--sarif=$report");

    is($result -> {status}, 0, 'the gate stays open without findings');
    ok(-f $report, 'the report file is created');
    is_deeply(read_json($report) -> {runs}[0]{results},
        [], 'the report has no results');
};
