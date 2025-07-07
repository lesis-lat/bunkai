#!/usr/bin/env perl

use 5.034;
use strict;
use warnings;
use utf8;

use Carp qw(croak);
use English qw(-no_match_vars);
use FindBin;
use lib './lib';

use Getopt::Long qw(GetOptions);
use Bunkai::Engine::Parser qw(parse_cpanfile);
use Bunkai::Utils::Helper  qw(get_interface_info);

our $VERSION = '0.0.1';

sub main {
    my ($project_path, $show_help);

    GetOptions(
        'path=s' => \$project_path,
        'help|h' => \$show_help,
    ) or croak get_interface_info();

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

    my $dependencies = parse_cpanfile($project_path);
    return render_analysis($dependencies);
}

sub render_analysis {
    my ($dependencies) = @_;

    my $exit_code = 0;
    for my $dep ( sort { $a->{module} cmp $b->{module} } @{$dependencies} ) {
        if ( $dep->{has_version} ) {
            printf {*STDOUT} "%-40s %s\n", $dep->{module}, $dep->{version}
              or croak "Cannot print dependency info to STDOUT: $OS_ERROR";
        }
        else {
            warn "Warning: Module '$dep->{module}' has no version specified.\n";
            $exit_code = 1; # Exit with failure on warnings
        }
    }

    return $exit_code;
}

exit main();