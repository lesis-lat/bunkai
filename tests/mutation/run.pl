#!/usr/bin/env perl

use strict;
use warnings;

use Carp       qw(croak);
use Cwd        qw(abs_path);
use English    qw(-no_match_vars);
use File::Copy qw(copy);
use File::Find qw(find);
use File::Path qw(make_path remove_tree);
use File::Spec;
use Getopt::Long qw(GetOptions);
use FindBin;
use Readonly;
use lib "$FindBin::Bin/../lib";

use Bunkai::Test::Directory;

our $VERSION = '0.1.0';

Readonly my $SHUFFLE_MODULUS    => 2_147_483_647;
Readonly my $SHUFFLE_MULTIPLIER => 48_271;
Readonly my $DEFAULT_SEED       => 20_260_914;
Readonly my $DEFAULT_TIMEOUT    => 120;
Readonly my $DEFAULT_MINIMUM    => 85;
Readonly my $PERCENT            => 100;

my @PROJECT = qw(lib tests bunkai.pl);

sub project_files {
    my @paths;

    for my $entry (@PROJECT) {
        if (-f $entry) {
            push @paths, $entry;

            next;
        }

        if (!-d $entry) {
            next;
        }

        find(
            {
                no_chdir => 1,
                wanted   => sub {
                    if (-f $File::Find::name) {
                        push @paths, $File::Find::name;
                    }

                    return;
                },
            },
            $entry
        );
    }

    my @sorted = sort @paths;

    return @sorted;
}

sub copy_project {
    my ($root) = @_;

    for my $path (project_files()) {
        my $target = File::Spec -> catfile($root, $path);
        my ($volume, $directory) = File::Spec -> splitpath($target);

        make_path($directory);
        copy($path, $target) or croak "cannot copy $path: $ERRNO";
    }

    return;
}

sub shuffled {
    my ($items, $seed) = @_;

    my $state = ($seed % $SHUFFLE_MODULUS) || 1;
    my @keyed;

    for my $item (@{$items}) {
        $state = ($state * $SHUFFLE_MULTIPLIER) % $SHUFFLE_MODULUS;

        push @keyed, {key => $state, item => $item};
    }

    my @order = map { $_ -> {item} }
      sort { $a -> {key} <=> $b -> {key} } @keyed;

    return \@order;
}

sub prune_mutants {
    my ($root, $limit, $seed) = @_;

    my $mutants_dir = File::Spec -> catdir($root, 'mutants');
    my @mutants =
      sort grep { -d } glob File::Spec -> catdir($mutants_dir, q{*});

    if ($limit <= 0 || @mutants <= $limit) {
        return scalar @mutants;
    }

    my $order = shuffled(\@mutants, $seed);

    for my $mutant (@{$order}[$limit .. $#{$order}]) {
        remove_tree($mutant);
    }

    return $limit;
}

sub run_mutator {
    my ($arguments) = @_;

    my $command = join q{ }, 'mutator', @{$arguments};

    open my $pipe, q{-|}, "$command 2>&1" or croak 'cannot run mutator';
    my @lines = <$pipe>;

    close $pipe or do { };

    return \@lines;
}

sub summarise {
    my ($lines) = @_;

    my $report = {
        killed    => 0,
        survived  => 0,
        timeout   => 0,
        survivors => [],
    };

    for my $line (@{$lines}) {
        my ($path, $status) = $line =~
          m{\A [(] \d+ / \d+ [)] \s+ (\S+) \s+ [.][.][.] \s+ (.+?) \s* \z}xms;

        if (!defined $status) {
            next;
        }

        if ($status eq 'ok') {
            $report -> {killed} = $report -> {killed} + 1;

            next;
        }

        if ($status =~ m{\A n/a}xms) {
            $report -> {timeout} = $report -> {timeout} + 1;

            next;
        }

        $report -> {survived} = $report -> {survived} + 1;

        push @{$report -> {survivors}}, $path;
    }

    return $report;
}

sub describe_survivor {
    my ($root, $path) = @_;

    my ($file) = $path =~ m{\A (?:[.]/)? mutants/[^/]+/(.*) \z}xms;

    if (!$file) {
        return $path;
    }

    my $original = File::Spec -> catfile($root, $file);
    my $mutant   = File::Spec -> catfile($root, $path);

    open my $handle, '<', $mutant or return $file;
    my @mutant_lines = <$handle>;
    close $handle or return $file;

    open my $source, '<', $original or return $file;
    my @source_lines = <$source>;
    close $source or return $file;

    for my $index (0 .. $#source_lines) {
        my $before = $source_lines[$index] // q{};
        my $after  = $mutant_lines[$index] // q{};

        if ($before ne $after) {
            $before =~ s/\A\s+|\s+\z//gxms;
            $after  =~ s/\A\s+|\s+\z//gxms;

            return sprintf '%s:%d %s -> %s', $file, $index + 1, $before,
              $after;
        }
    }

    return $file;
}

sub carton_library {
    my $vendored = abs_path('local/lib/perl5');

    if (!defined $vendored || !-d $vendored) {
        return;
    }

    return $vendored;
}

sub main {
    my $limit   = 0;
    my $seed    = $DEFAULT_SEED;
    my $suite   = 'tests/unit tests/integration';
    my $timeout = $DEFAULT_TIMEOUT;
    my $minimum = $DEFAULT_MINIMUM;
    my $quiet;

    GetOptions(
        'l|limit=i'   => \$limit,
        's|seed=i'    => \$seed,
        't|tests=s'   => \$suite,
        'o|timeout=i' => \$timeout,
        'm|minimum=i' => \$minimum,
        'q|quiet'     => \$quiet,
    ) or croak 'cannot parse the command line';

    my $origin   = File::Spec -> rel2abs(q{.});
    my $vendored = carton_library();
    my $root     = Bunkai::Test::Directory -> new();

    local $ENV{PERL5LIB} = join q{:},
      grep { defined && length } ($vendored, $ENV{PERL5LIB});

    copy_project($root);

    chdir $root or croak "cannot enter $root";

    my $generated = run_mutator(['mutate', '-r', 'lib bunkai.pl']);

    print @{$generated}
      or croak "cannot report the generated mutants: $ERRNO";

    my $total = prune_mutants($root, $limit, $seed);

    printf "Running %d mutants against %s\n\n", $total, $suite
      or croak "cannot report the plan: $ERRNO";

    my $command = "prove -Ilib -Itests/lib -r $suite";

    my $lines =
      run_mutator(['test', '--timeout', $timeout, '--command', "'$command'"]);

    if (!$quiet) {
        print @{$lines} or croak "cannot report the run: $ERRNO";
    }

    my $report = summarise($lines);
    my $scored = $report -> {killed} + $report -> {survived};
    my $score  = $PERCENT;

    if ($scored) {
        $score = $PERCENT * $report -> {killed} / $scored;
    }

    printf
      "\nKilled %d, survived %d, timed out %d\nMutation score: %.1f%%\n",
      $report -> {killed}, $report -> {survived}, $report -> {timeout}, $score
      or croak "cannot report the score: $ERRNO";

    if (@{$report -> {survivors}}) {
        print "\nSurviving mutants:\n"
          or croak "cannot report the survivors: $ERRNO";

        for my $path (@{$report -> {survivors}}) {
            print q{  } . describe_survivor($root, $path) . "\n"
              or croak "cannot describe a survivor: $ERRNO";
        }
    }

    chdir $origin or croak "cannot return to $origin";

    if ($score < $minimum) {
        printf "\nThe mutation score is below the %d%% floor.\n", $minimum
          or croak "cannot report the floor: $ERRNO";

        return 1;
    }

    return 0;
}

exit main();
