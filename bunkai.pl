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
use Bunkai::Engine::Analyzer qw(analyze_dependencies);
use Bunkai::Engine::Auditor  qw(audit_dependencies);
use Bunkai::Engine::Parser   qw(parse_cpanfile);
use Bunkai::Utils::Helper    qw(get_interface_info);

our $VERSION = '0.0.3';

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

    my $parser_result = parse_cpanfile($project_path);

    if ( !$parser_result->{success} ) {
        print {*STDERR} "Warning: 'cpanfile' not found in '$project_path'.\n"
            or croak "Cannot print warning to STDERR: $OS_ERROR";
        return 1;
    }

    my $analyzed_deps = analyze_dependencies( $parser_result->{data} );
    my $audited_deps = audit_dependencies($analyzed_deps);

    return render_analysis($audited_deps);
}

sub render_analysis {
    my ($dependencies) = @_;
    my $exit_code = 0;

    for my $dep ( @{$dependencies} ) {
        my $version_display = $dep->{has_version} ? $dep->{version} : 'not specified';
        printf {*STDOUT} "%-40s %s\n", $dep->{module}, $version_display
          or croak "Cannot print dependency info to STDOUT: $OS_ERROR";

        if ( !$dep->{has_version} ) {
            print {*STDERR} "Warning: Module '$dep->{module}' has no version specified.\n"
                or croak "Cannot print warning to STDERR: $OS_ERROR";
            $exit_code = 1;
        }

        if ( $dep->{is_outdated} ) {
            print {*STDERR} sprintf "Warning: Module '%s' is outdated. Specified: %s, Latest: %s\n",
                $dep->{module}, $dep->{version}, $dep->{latest_version}
              or croak "Cannot print warning to STDERR: $OS_ERROR";
            $exit_code = 1;
        }
        elsif ( $dep->{has_version} && !defined $dep->{latest_version} ) {
            print {*STDERR} "Warning: Could not fetch latest version for '$dep->{module}'.\n"
                or croak "Cannot print warning to STDERR: $OS_ERROR";
        }

        if ( $dep->{has_vulnerabilities} ) {
            for my $vuln ( @{$dep->{vulnerabilities}} ) {
                print {*STDERR} sprintf "SECURITY: Module '%s' has vulnerability %s: %s\n",
                    $dep->{module}, $vuln->{cve_id}, $vuln->{description}
                  or croak "Cannot print security warning to STDERR: $OS_ERROR";

                if ( $vuln->{fixed_version} ) {
                    print {*STDERR} sprintf "  Suggest: Upgrade to version %s or later.\n",
                        $vuln->{fixed_version}
                      or croak "Cannot print upgrade suggestion to STDERR: $OS_ERROR";
                }
            }
            $exit_code = 1;
        }
    }

    return $exit_code;
}

exit main();
