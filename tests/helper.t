#!/usr/bin/env perl

use 5.034;
use strict;
use warnings;

use Test::More;
use lib '../lib/';
use Bunkai::Utils::Helper qw(get_interface_info);

our $VERSION = '0.0.1';

subtest 'interface info retrieval' => sub {
    my $info = get_interface_info();
    like(
        $info,
        qr{ Bunkai \s v \d+ [.] \d+ [.] \d+ }msx,
        'Help text contains the tool name and version'
    );
    like( $info, qr{ SCA \s for \s Perl \s Projects }msx, 'Help text contains the description' );
    like( $info, qr{ --path }msx, 'Help text contains the --path option' );
    like( $info, qr{ --help }msx, 'Help text contains the --help option' );
};

done_testing();