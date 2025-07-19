#!/usr/bin/env perl

use 5.034;
use strict;
use warnings;

use Test::More;
use Test::MockModule;
use lib '../lib/';
use Bunkai::Engine::Fetcher qw(fetch_latest_version);
use Carp qw(croak);

our $VERSION = '0.0.4';

sub MockedClient::module { croak 'MockedClient::module not localized' }
sub MockedModule::version { croak 'MockedModule::version not localized' }

subtest 'fetch latest version' => sub {
    my $mcpan_class_mock = Test::MockModule->new('MetaCPAN::Client');

    subtest 'when module is found' => sub {
        my $mock_module_obj = bless {}, 'MockedModule';
        my $mock_client_obj = bless {}, 'MockedClient';

        local *MockedModule::version = sub {'1.23'};
        local *MockedClient::module  = sub { return $mock_module_obj };

        $mcpan_class_mock->redefine( new => sub {$mock_client_obj} );
        is( fetch_latest_version('Some::Module'), '1.23', 'Returns correct version' );
    };

    subtest 'when module is not found' => sub {
        my $mock_client_obj = bless {}, 'MockedClient';
        local *MockedClient::module = sub {undef};

        $mcpan_class_mock->redefine( new => sub {$mock_client_obj} );
        is( fetch_latest_version('Unknown::Module'), undef, 'Returns undef for unknown module' );
    };

    subtest 'when a network error occurs' => sub {
        my $mock_client_obj = bless {}, 'MockedClient';
        local *MockedClient::module = sub { croak 'Network error' };

        $mcpan_class_mock->redefine( new => sub {$mock_client_obj} );
        is( fetch_latest_version('Any::Module'), undef, 'Returns undef on API error' );
    };
};

done_testing();
