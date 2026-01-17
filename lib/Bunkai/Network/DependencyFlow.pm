package Bunkai::Network::DependencyFlow;

use 5.034;
use strict;
use warnings;

use Carp qw(croak);
use English qw(-no_match_vars);
use Exporter qw(import);

use Bunkai::Component::Analyzer qw(analyze_dependencies);
use Bunkai::Component::Auditor qw(audit_dependencies);
use Bunkai::Component::Parser qw(parse_cpanfile);
use Bunkai::Component::Updater qw(plan_cpanfile_updates apply_cpanfile_updates);
use Bunkai::Component::AnalysisRenderer qw(render_analysis);
use Bunkai::Component::SarifWriter qw(write_sarif_report);

our @EXPORT_OK = qw(run_flow);
our $VERSION   = '0.0.4';

sub run_flow {
    my (%options) = @_;

    my $project_path = $options{project_path};
    my $sarif_output_file = $options{sarif_output_file};
    my $update_cpanfile = $options{update_cpanfile};

    my $parser_result = parse_cpanfile($project_path);

    if ( !$parser_result -> {success} ) {
        return +{
            success   => 0,
            exit_code => 1,
            message   => "Warning: 'cpanfile' not found in '$project_path'.",
        };
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
            return +{ success => 1, exit_code => 0 };
        }

        print {*STDOUT} "No cpanfile updates required.\n"
          or croak "Cannot print update summary to STDOUT: $OS_ERROR";
        return +{ success => 1, exit_code => 0 };
    }

    if ( defined $sarif_output_file ) {
        my $output_filename = 'bunkai_results.sarif';
        if ( defined $sarif_output_file && length $sarif_output_file ) {
            $output_filename = $sarif_output_file;
        }
        write_sarif_report(
            $audited_dependencies,
            $parser_result -> {cpanfile_path},
            $output_filename
        );
    }

    my $exit_code = render_analysis($audited_dependencies);

    return +{
        success   => 1,
        exit_code => $exit_code,
    };
}

1;
