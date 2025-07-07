#!/usr/bin/env perl

use 5.034;
use strict;
use warnings;

use Test::More;
use lib '../lib/';
use File::Temp qw(tempdir);
use Path::Tiny qw(path);
use Bunkai::Engine::Parser qw(parse_cpanfile);

our $VERSION = '0.0.1';

subtest 'with a valid cpanfile' => sub {
    my $dir = tempdir( CLEANUP => 1 );
    my $cpanfile = path($dir)->child('cpanfile');
    $cpanfile->spew("requires 'Mojolicious', '==9.31';\nrequires 'Plack';\n");

    my $deps = parse_cpanfile($dir);

    is_deeply(
        [ sort { $a->{module} cmp $b->{module} } @{$deps} ],
        [
            { module => 'Mojolicious', version => '9.31', has_version => 1 },
            { module => 'Plack',       version => undef,  has_version => 0 },
        ],
        'Correctly parses modules with and without versions'
    );
};

subtest 'with a non-existent cpanfile' => sub {
    my $dir = tempdir( CLEANUP => 1 );
    my $deps = parse_cpanfile($dir);
    is_deeply( $deps, [], 'Returns an empty list for missing cpanfile' );
};

subtest 'with an empty cpanfile' => sub {
    my $dir = tempdir( CLEANUP => 1 );
    path($dir)->child('cpanfile')->touch;
    my $deps = parse_cpanfile($dir);
    is_deeply( $deps, [], 'Returns an empty list for empty cpanfile' );
};

done_testing();