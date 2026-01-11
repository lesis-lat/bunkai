#!/usr/bin/env perl

use 5.034;
use strict;
use warnings;
use utf8;

use Carp qw(croak);
use English qw(-no_match_vars);
use FindBin qw($Bin);
use lib "$Bin/lib";

use JSON::PP;
use Getopt::Long qw(GetOptions);
use Bunkai::Engine::Analyzer qw(analyze_dependencies);
use Bunkai::Engine::Auditor  qw(audit_dependencies);
use Bunkai::Engine::Parser   qw(parse_cpanfile);
use Bunkai::Engine::Updater  qw(plan_cpanfile_updates apply_cpanfile_updates);
use Bunkai::Utils::Helper    qw(get_interface_info);
use Bunkai::Utils::Sarif     qw(generate_sarif);

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

    my $parser_result = parse_cpanfile($project_path);

    if ( !$parser_result -> {success} ) {
        print {*STDERR} "Warning: 'cpanfile' not found in '$project_path'.\n"
          or croak "Cannot print warning to STDERR: $OS_ERROR";
        return 1;
    }

    my $analyzed_dependencies = analyze_dependencies( $parser_result -> {data} );
    my $audited_dependencies  = audit_dependencies($analyzed_dependencies);

    if ($update_cpanfile) {
        my $updates = plan_cpanfile_updates($audited_dependencies);
        my $updated_count =
          apply_cpanfile_updates( $parser_result -> {cpanfile_path}, $updates );

        if ( @{$updates} ) {
            for my $update ( @{$updates} ) {
                printf {*STDOUT} "UPDATE: %s %s\n", $update -> {module}, $update -> {version}
                  or croak "Cannot print update info to STDOUT: $OS_ERROR";
            }

            print {*STDOUT} "Updated cpanfile entries: $updated_count\n"
              or croak "Cannot print update summary to STDOUT: $OS_ERROR";
        }
        else {
            print {*STDOUT} "No cpanfile updates required.\n"
              or croak "Cannot print update summary to STDOUT: $OS_ERROR";
        }

        return 0;
    }

    if ( defined $sarif_output_file ) {
        my $output_filename =
          $sarif_output_file || 'bunkai_results.sarif';
        write_sarif_report( $audited_dependencies, $parser_result -> {cpanfile_path},
            $output_filename );
    }

    return render_analysis($audited_dependencies);
}

sub generate_report_for_dependency {
    my ($dependency) = @_;

    my @report_lines;
    my $should_fail = 0;
    my $warning_line;
    my $suggest_line;
    my @security_lines;
    my @error_lines;

    if ( !$dependency -> {has_version} ) {
        $warning_line = "WARNING: Module '$dependency -> {module}' has no version specified.";
        $should_fail  = 1;
    }
    elsif ( $dependency -> {is_outdated} ) {
        $warning_line =
          sprintf q{WARNING: Module '%s' is outdated. Specified: %s, Latest: %s},
          $dependency -> {module}, $dependency -> {version}, $dependency -> {latest_version};
        $should_fail = 1;
    }
    elsif ( $dependency -> {has_version} && !defined $dependency -> {latest_version} ) {
        $warning_line = sprintf q{WARNING: Could not fetch latest version for '%s'.}, $dependency -> {module};
    }

    if ( $dependency -> {has_vulnerabilities} ) {
        $should_fail = 1;
        for my $vulnerability ( @{ $dependency -> {vulnerabilities} } ) {
            if ( $vulnerability -> {type} eq 'error' ) {
                push @error_lines, $vulnerability -> {description};
                next;
            }

            if ( !$suggest_line && defined $vulnerability -> {fixed_version} ) {
                $suggest_line =
                  sprintf 'SUGGEST: Upgrade to version %s or later.', $vulnerability -> {fixed_version};
            }

            my $security_report = sprintf "SECURITY: Module '%s' has vulnerability %s:\n%s",
              $dependency -> {module}, $vulnerability -> {cve_id}, $vulnerability -> {description};
            push @security_lines, $security_report;
        }
    }

    if ( !$suggest_line && $dependency -> {is_outdated} ) {
        $suggest_line =
          sprintf 'SUGGEST: Upgrade to version %s or later.', $dependency -> {latest_version};
    }

    if ($warning_line)   { push @report_lines, $warning_line; }
    if ($suggest_line)   { push @report_lines, $suggest_line; }
    if (@security_lines) { push @report_lines, @security_lines; }
    if (@error_lines)    { push @report_lines, @error_lines; }

    return ( \@report_lines, $should_fail );
}

sub render_analysis {
    my ($dependencies) = @_;
    my $exit_code = 0;

    for my $dependency ( @{$dependencies} ) {
        my $version_display = $dependency -> {has_version} ? $dependency -> {version} : 'not specified';
        printf {*STDOUT} "%-40s %s\n", $dependency -> {module}, $version_display
          or croak "Cannot print dependency info to STDOUT: $OS_ERROR";

        my ( $report_lines, $has_issues ) = generate_report_for_dependency($dependency);

        if ($has_issues) {
            $exit_code = 1;
        }

        if ( @{$report_lines} ) {
            print {*STDERR} join( "\n", @{$report_lines} ), "\n"
              or croak "Cannot print report to STDERR: $OS_ERROR";
        }
    }

    return $exit_code;
}

sub write_sarif_report {
    my ( $dependencies, $cpanfile_path, $output_file ) = @_;

    my $sarif_data = generate_sarif( $dependencies, $cpanfile_path );
    my $json       = JSON::PP -> new -> pretty -> encode($sarif_data);

    open my $fh, '>', $output_file
      or croak "Cannot open SARIF output file '$output_file': $OS_ERROR";
    print {$fh} $json
      or croak "Cannot write to SARIF output file '$output_file': $OS_ERROR";
    close $fh
      or croak "Cannot close SARIF output file '$output_file': $OS_ERROR";

    return;
}

exit main();
