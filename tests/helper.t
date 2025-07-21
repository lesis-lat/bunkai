#!/usr/bin/env perl

use 5.034;
use strict;
use warnings;

use Test::More;
use lib '../lib/';
use Bunkai::Utils::Helper qw(get_interface_info);

our $VERSION = '0.0.4';

subtest 'interface info retrieval' => sub {
    my $info = get_interface_info();
    like(
        $info,
        qr{ Bunkai \s v \d+ [.] \d+ [.] \d+ }msx,
        'Help text contains the tool name and version'
    );
    like( $info, qr{ SCA \s for \s Perl \s Projects }msx, 'Help text contains the description' );
    like( $info, qr{ -p, \s --path=PATH }msx, 'Help text contains the --path option with short form' );
    like( $info, qr{ -s, \s --sarif }msx, 'Help text contains the --sarif option with short form' );
    like( $info, qr{ -h, \s --help }msx, 'Help text contains the --help option with short form' );
    like( $info, qr{ Path \s to \s the \s project \s containing \s a \s cpanfile }msx, 'Help text contains path description' );
    like( $info, qr{ Output \s results \s to \s a \s SARIF \s file }msx, 'Help text contains SARIF description' );
    like( $info, qr{ Display \s this \s help \s menu }msx, 'Help text contains help description' );
    like( $info, qr{ Command \s+ Description }msx, 'Help text contains table header' );
    like( $info, qr{ ={5,} }msx, 'Help text contains separator line' );
};

done_testing();
