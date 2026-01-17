package Bunkai::Component::ReportGenerator;

use 5.034;
use strict;
use warnings;

use Exporter qw(import);

our @EXPORT_OK = qw(generate_report_for_dependency);
our $VERSION   = '0.0.4';

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

    if ( $dependency -> {has_version} && $dependency -> {is_outdated} ) {
        $warning_line =
          sprintf q{WARNING: Module '%s' is outdated. Specified: %s, Latest: %s},
          $dependency -> {module}, $dependency -> {version}, $dependency -> {latest_version};
        $should_fail = 1;
    }

    if ( $dependency -> {has_version} && !defined $dependency -> {latest_version} ) {
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

    if ($warning_line) {
        push @report_lines, $warning_line;
    }

    if ($suggest_line) {
        push @report_lines, $suggest_line;
    }

    if (@security_lines) {
        push @report_lines, @security_lines;
    }

    if (@error_lines) {
        push @report_lines, @error_lines;
    }

    return ( \@report_lines, $should_fail );
}

1;
