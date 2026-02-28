package Bunkai::Component::AnalysisRenderer;

use 5.034;
use strict;
use warnings;

use Carp qw(croak);
use English qw(-no_match_vars);
use Exporter qw(import);

use Bunkai::Component::ReportGenerator qw(generate_report_for_dependency);

our @EXPORT_OK = qw(render_analysis);
our $VERSION   = '0.0.4';

sub render_analysis {
    my ($dependencies) = @_;
    my $exit_code = 0;

    for my $dependency ( @{$dependencies} ) {
        my $version_display = 'not specified';
        if ( $dependency -> {has_version} ) {
            $version_display = $dependency -> {version};
        }
        printf {*STDOUT} "%-40s %s\n", $dependency -> {module}, $version_display
          or croak "Cannot print dependency info to STDOUT: $OS_ERROR";

        my ( $report_lines, $has_issues ) = generate_report_for_dependency($dependency);

        if ($has_issues) {
            $exit_code = 1;
        }

        if ( @{$report_lines} ) {
            print {*STDOUT} join( "\n", @{$report_lines} ), "\n"
              or croak "Cannot print report to STDOUT: $OS_ERROR";
        }
    }

    return $exit_code;
}

1;
