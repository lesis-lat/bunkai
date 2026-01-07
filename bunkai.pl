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
use Bunkai::Utils::Helper    qw(get_interface_info);
use Bunkai::Utils::Sarif     qw(generate_sarif);

our $VERSION = '0.0.4';

sub main {
    my ( $project_path, $show_help, $sarif_output_file );

    GetOptions(
        'path=s'    => \$project_path,
        'sarif|s:s' => \$sarif_output_file,
        'help|h'    => \$show_help,
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

    if ( !$parser_result->{success} ) {
        print {*STDERR} "Warning: 'cpanfile' not found in '$project_path'.\n"
          or croak "Cannot print warning to STDERR: $OS_ERROR";
        return 1;
    }

    my $analyzed_deps = analyze_dependencies( $parser_result->{data} );
    my $audited_deps  = audit_dependencies($analyzed_deps);

    if ( defined $sarif_output_file ) {
        my $output_filename =
          $sarif_output_file || 'bunkai_results.sarif';
        write_sarif_report( $audited_deps, $parser_result->{cpanfile_path},
            $output_filename );
    }

    return render_analysis($audited_deps);
}

sub generate_report_for_dep {
    my ($dep) = @_;

    my @report_lines;
    my $should_fail = 0;
    my $warning_line;
    my $suggest_line;
    my @security_lines;
    my @error_lines;

    if ( !$dep->{has_version} ) {
        $warning_line = "WARNING: Module '$dep->{module}' has no version specified.";
        $should_fail  = 1;
    }
    elsif ( $dep->{is_outdated} ) {
        $warning_line =
          sprintf q{WARNING: Module '%s' is outdated. Specified: %s, Latest: %s},
          $dep->{module}, $dep->{version}, $dep->{latest_version};
        $should_fail = 1;
    }
    elsif ( $dep->{has_version} && !defined $dep->{latest_version} ) {
        $warning_line = sprintf q{WARNING: Could not fetch latest version for '%s'.}, $dep->{module};
    }

    if ( $dep->{has_vulnerabilities} ) {
        $should_fail = 1;
        for my $vuln ( @{ $dep->{vulnerabilities} } ) {
            if ( $vuln->{type} eq 'error' ) {
                push @error_lines, $vuln->{description};
                next;
            }

            if ( !$suggest_line && defined $vuln->{fixed_version} ) {
                $suggest_line =
                  sprintf 'SUGGEST: Upgrade to version %s or later.', $vuln->{fixed_version};
            }

            my $security_report = sprintf "SECURITY: Module '%s' has vulnerability %s:\n%s",
              $dep->{module}, $vuln->{cve_id}, $vuln->{description};
            push @security_lines, $security_report;
        }
    }

    if ( !$suggest_line && $dep->{is_outdated} ) {
        $suggest_line =
          sprintf 'SUGGEST: Upgrade to version %s or later.', $dep->{latest_version};
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

    for my $dep ( @{$dependencies} ) {
        my $version_display = $dep->{has_version} ? $dep->{version} : 'not specified';
        printf {*STDOUT} "%-40s %s\n", $dep->{module}, $version_display
          or croak "Cannot print dependency info to STDOUT: $OS_ERROR";

        my ( $report_lines, $has_issues ) = generate_report_for_dep($dep);

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
    my $json       = JSON::PP->new->pretty->encode($sarif_data);

    open my $fh, '>', $output_file
      or croak "Cannot open SARIF output file '$output_file': $OS_ERROR";
    print {$fh} $json
      or croak "Cannot write to SARIF output file '$output_file': $OS_ERROR";
    close $fh
      or croak "Cannot close SARIF output file '$output_file': $OS_ERROR";

    return;
}

exit main();
