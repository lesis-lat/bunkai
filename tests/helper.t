#!/usr/bin/env perl

package main;

use 5.034;
use strict;
use warnings;

use Test::More;
use lib '../lib/';
use Bunkai::Utils::Helper qw(get_interface_info);

our $VERSION = '0.0.4';
my $TOOL_VERSION_PATTERN = qr{
    Bunkai \s v
    [[:digit:]]+
    [.]
    [[:digit:]]+
    [.]
    [[:digit:]]+
}xms;

subtest 'interface info retrieval' => sub {
    my $info = get_interface_info();
    like(
        $info,
        $TOOL_VERSION_PATTERN,
        'Help text contains the tool name and version'
    );
    like( $info, qr{ SCA \s for \s Perl \s Projects }msx, 'Help text contains the description' );
    like( $info, qr{ -p, \s --path=PATH }msx, 'Help text contains the --path option with short form' );
    like( $info, qr{ -s, \s --sarif }msx, 'Help text contains the --sarif option with short form' );
    like( $info, qr{ -u, \s --update-cpanfile }msx, 'Help text contains the --update-cpanfile option with short form' );
    like( $info, qr{ -P, \s --plan-updates }msx, 'Help text contains the --plan-updates option with short form' );
    like( $info, qr{ --apply-update-id=ID }msx, 'Help text contains the --apply-update-id option' );
    like( $info, qr{ -h, \s --help }msx, 'Help text contains the --help option with short form' );
    like( $info, qr{ Path \s to \s the \s project \s containing \s a \s cpanfile }msx, 'Help text contains path description' );
    like( $info, qr{ Output \s results \s to \s a \s SARIF \s file }msx, 'Help text contains SARIF description' );
    like(
        $info,
        qr{\QUpdate cpanfile with latest or fixed dependency versions\E}xms,
        'Help text contains update-cpanfile description'
    );
    like( $info, qr{ Write \s issue-scoped \s cpanfile \s updates \s to \s JSON }msx, 'Help text contains plan-updates description' );
    like( $info, qr{ Apply \s a \s single \s issue-scoped \s update \s by \s ID }msx, 'Help text contains apply-update-id description' );
    like( $info, qr{ Display \s this \s help \s menu }msx, 'Help text contains help description' );
    like( $info, qr{ Command \s+ Description }msx, 'Help text contains table header' );
    like( $info, qr{ ={5,} }msx, 'Help text contains separator line' );
};

done_testing();
