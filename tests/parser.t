#!/usr/bin/env perl

package main;

use 5.034;
use strict;
use warnings;

use Test::More;
use lib '../lib/';
use File::Temp qw(tempdir);
use Path::Tiny qw(path);
use Bunkai::Engine::Parser qw(parse_cpanfile);

our $VERSION = '0.0.4';

subtest 'with a valid cpanfile' => sub {
    my $dir      = tempdir( CLEANUP => 1 );
    my $cpanfile = path($dir) -> child('cpanfile');
    $cpanfile -> spew("requires 'Plack';\nrequires 'Mojolicious', '==9.31';\n");

    my $result = parse_cpanfile($dir);

    is( $result -> {success}, 1, 'Parsing is marked as successful' );
    is_deeply(
        $result -> {data},
        [
            { module => 'Mojolicious', version => '9.31', has_version => 1 },
            { module => 'Plack',       version => undef,  has_version => 0 },
        ],
        'Correctly parses modules with and without versions'
    );
};

subtest 'with a non-existent cpanfile' => sub {
    my $dir    = tempdir( CLEANUP => 1 );
    my $result = parse_cpanfile($dir);
    is( $result -> {success}, 0, 'Parsing is marked as unsuccessful' );
    is( $result -> {reason}, 'cpanfile_not_found', 'Reason is cpanfile_not_found' );
    is_deeply( $result -> {data}, [], 'Data is an empty list for missing cpanfile' );
};

subtest 'with an empty cpanfile' => sub {
    my $dir = tempdir( CLEANUP => 1 );
    path($dir) -> child('cpanfile') -> touch;
    my $result = parse_cpanfile($dir);
    is( $result -> {success}, 1, 'Parsing is marked as successful for empty file' );
    is_deeply( $result -> {data}, [], 'Returns an empty list for empty cpanfile' );
};

done_testing();
