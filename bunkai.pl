#!/usr/bin/env perl

package main;

use 5.034;
use strict;
use warnings;
use utf8;

use Carp qw(croak);
use English qw(-no_match_vars);
use FindBin qw($Bin);
use lib "$Bin/lib";

use Getopt::Long qw(GetOptions);
use Bunkai::Network::DependencyFlow qw(run_flow);
use Bunkai::Utils::Helper qw(get_interface_info);

our $VERSION = '0.0.4';

sub main {
    my ( $project_path, $show_help, $sarif_output_file, $update_cpanfile );

    GetOptions(
        'path=s'            => \$project_path,
        'sarif|s:s'         => \$sarif_output_file,
        'update-cpanfile|u' => \$update_cpanfile,
        'help|h'            => \$show_help,
      )
      or croak get_interface_info();

    if ($show_help) {
        print {*STDOUT} get_interface_info()
          or croak "Cannot print help message: $OS_ERROR";
        return 0;
    }

    if ( !($project_path && -d $project_path) ) {
        print {*STDERR} "Error: --path is required and must be a valid directory.\n\n"
          or croak "Cannot print error message to STDERR: $OS_ERROR";
        print {*STDOUT} get_interface_info()
          or croak "Cannot print help message: $OS_ERROR";
        return 1;
    }

    my $result = run_flow(
        project_path      => $project_path,
        sarif_output_file => $sarif_output_file,
        update_cpanfile   => $update_cpanfile,
    );

    if ( !$result -> {success} ) {
        my $message = $result -> {message};
        print {*STDERR} "$message\n"
          or croak "Cannot print warning to STDERR: $OS_ERROR";
        return $result -> {exit_code};
    }

    return $result -> {exit_code};
}

exit main();
