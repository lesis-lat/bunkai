package Bunkai::Network::DependencyFlow;

use 5.034;
use strict;
use warnings;

use Carp qw(croak);
use English qw(-no_match_vars);
use Exporter qw(import);
use JSON::PP;

use Bunkai::Component::AnalysisRenderer qw(render_analysis);
use Bunkai::Component::Analyzer qw(analyze_dependencies);
use Bunkai::Component::Auditor qw(audit_dependencies);
use Bunkai::Component::Parser qw(parse_cpanfile);
use Bunkai::Component::SarifWriter qw(write_sarif_report);
use Bunkai::Component::Updater qw(
  apply_cpanfile_updates
  plan_cpanfile_updates
  plan_issue_updates
  plan_single_update_by_issue_id
);

our @EXPORT_OK = qw(run_flow);
our $VERSION   = '0.0.4';

sub parse_project_dependencies {
    my ($project_path) = @_;

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

    return +{
        success               => 1,
        audited_dependencies  => $audited_dependencies,
        cpanfile_path         => $parser_result -> {cpanfile_path},
        planned_issue_updates => plan_issue_updates($audited_dependencies),
    };
}

sub write_updates_plan {
    my ( $project_path, $plan_updates_file, $planned_issue_updates ) = @_;

    if ( !defined $plan_updates_file ) {
        return;
    }

    my $output_filename = 'bunkai_updates.json';
    if ( length $plan_updates_file ) {
        $output_filename = $plan_updates_file;
    }

    my $plan_document = +{
        generated_at => time,
        project_path => $project_path,
        issues       => $planned_issue_updates,
    };
    my $plan_json = JSON::PP -> new -> pretty -> encode($plan_document);

    open my $updates_fh, '>', $output_filename
      or croak "Cannot open updates plan file '$output_filename': $OS_ERROR";
    print {$updates_fh} $plan_json
      or croak "Cannot write updates plan file '$output_filename': $OS_ERROR";
    close $updates_fh
      or croak "Cannot close updates plan file '$output_filename': $OS_ERROR";

    print {*STDOUT} "Planned updates written to $output_filename\n"
      or croak "Cannot print plan summary to STDOUT: $OS_ERROR";

    return;
}

sub apply_single_update {
    my ( $audited_dependencies, $cpanfile_path, $apply_update_id ) = @_;

    if ( !defined $apply_update_id || !length $apply_update_id ) {
        return +{ success => 1 };
    }

    my $updates = plan_single_update_by_issue_id( $audited_dependencies, $apply_update_id );
    if ( !defined $updates ) {
        return +{
            success   => 0,
            exit_code => 1,
            message   => "Error: update issue id '$apply_update_id' was not found.",
        };
    }

    my $updated_count = apply_cpanfile_updates( $cpanfile_path, $updates );
    if ($updated_count) {
        my $update = $updates -> [0];
        printf {*STDOUT} "UPDATE: %s %s (%s)\n",
          $update -> {module},
          $update -> {version},
          $apply_update_id
          or croak "Cannot print update info to STDOUT: $OS_ERROR";
        print {*STDOUT} "Updated cpanfile entries: $updated_count\n"
          or croak "Cannot print update summary to STDOUT: $OS_ERROR";
    }
    else {
        print {*STDOUT} "No cpanfile updates required for issue '$apply_update_id'.\n"
          or croak "Cannot print update summary to STDOUT: $OS_ERROR";
    }

    return +{ success => 1 };
}

sub apply_bulk_updates {
    my ( $audited_dependencies, $cpanfile_path, $update_cpanfile ) = @_;

    if ( !$update_cpanfile ) {
        return;
    }

    my $updates = plan_cpanfile_updates($audited_dependencies);
    my $updated_count = apply_cpanfile_updates( $cpanfile_path, $updates );

    if ( @{$updates} ) {
        for my $update ( @{$updates} ) {
            printf {*STDOUT} "UPDATE: %s %s\n", $update -> {module}, $update -> {version}
              or croak "Cannot print update info to STDOUT: $OS_ERROR";
        }

        print {*STDOUT} "Updated cpanfile entries: $updated_count\n"
          or croak "Cannot print update summary to STDOUT: $OS_ERROR";
        return;
    }

    print {*STDOUT} "No cpanfile updates required.\n"
      or croak "Cannot print update summary to STDOUT: $OS_ERROR";

    return;
}

sub write_sarif_if_requested {
    my ( $audited_dependencies, $cpanfile_path, $sarif_output_file ) = @_;

    if ( !defined $sarif_output_file ) {
        return;
    }

    my $output_filename = 'bunkai_results.sarif';
    if ( length $sarif_output_file ) {
        $output_filename = $sarif_output_file;
    }
    write_sarif_report( $audited_dependencies, $cpanfile_path, $output_filename );

    return;
}

sub should_force_success_exit {
    my ( $sarif_output_file, $update_cpanfile, $plan_updates_file, $apply_update_id ) = @_;

    if (
        defined $sarif_output_file
        || $update_cpanfile
        || ( defined $plan_updates_file )
        || ( defined $apply_update_id && length $apply_update_id )
      )
    {
        return 1;
    }

    return 0;
}

sub run_flow {
    my (%options) = @_;

    my $project_path      = $options{project_path};
    my $sarif_output_file = $options{sarif_output_file};
    my $update_cpanfile   = $options{update_cpanfile};
    my $plan_updates_file = $options{plan_updates_file};
    my $apply_update_id   = $options{apply_update_id};

    my $dependency_result = parse_project_dependencies($project_path);
    if ( !$dependency_result -> {success} ) {
        return $dependency_result;
    }

    my $audited_dependencies = $dependency_result -> {audited_dependencies};
    my $cpanfile_path = $dependency_result -> {cpanfile_path};

    write_updates_plan(
        $project_path,
        $plan_updates_file,
        $dependency_result -> {planned_issue_updates}
    );

    my $single_update_result =
      apply_single_update( $audited_dependencies, $cpanfile_path, $apply_update_id );
    if ( !$single_update_result -> {success} ) {
        return $single_update_result;
    }

    apply_bulk_updates( $audited_dependencies, $cpanfile_path, $update_cpanfile );
    write_sarif_if_requested( $audited_dependencies, $cpanfile_path, $sarif_output_file );

    my $exit_code = render_analysis($audited_dependencies);
    if ( should_force_success_exit( $sarif_output_file, $update_cpanfile, $plan_updates_file, $apply_update_id ) ) {
        $exit_code = 0;
    }

    return +{
        success   => 1,
        exit_code => $exit_code,
    };
}

1;
