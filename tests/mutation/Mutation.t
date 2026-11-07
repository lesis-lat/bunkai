#!/usr/bin/env perl

use strict;
use warnings;

use FindBin;
use Test::More;

our $VERSION = '0.0.1';

if (!$ENV{BUNKAI_MUTATION}) {
    plan skip_all => 'set BUNKAI_MUTATION=1 to run the mutation suite';
}

my ($limit) = ($ENV{BUNKAI_MUTATION_LIMIT} || '40') =~ /\A(\d+)\z/xms;
my ($minimum) =
  ($ENV{BUNKAI_MUTATION_SCORE} || '85') =~ /\A(\d+)\z/xms;

if (!defined $limit || !defined $minimum) {
    plan skip_all => 'the mutation limit and score must be whole numbers';
}

plan tests => 5;

my $runner  = "$FindBin::Bin/run.pl";
my $command = "perl $runner --limit $limit --minimum $minimum --quiet";
my $output  = qx{$command 2>&1};                                          ## no critic (InputOutput::ProhibitBacktickOperators)

diag $output;

like($output, qr/Running\s\d+\smutants/xms, 'the runner generated mutants');

my ($score) = $output =~ /Mutation\sscore:\s([\d.]+)%/xms;

ok(defined $score, 'the runner reported a score');

cmp_ok($score, '>=', $minimum, "the mutation score is at least $minimum%");

my ($killed, $survived) = $output =~ /Killed\s(\d+),\ssurvived\s(\d+)/xms;

ok($killed > 0,       'at least one mutant was killed');
ok(defined $survived, 'the survivors are reported');
