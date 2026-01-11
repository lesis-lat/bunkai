package Bunkai::Utils::Sarif;

use 5.034;
use strict;
use warnings;

use Exporter qw(import);
use Carp qw(croak);
use Const::Fast;

our @EXPORT_OK = qw(generate_sarif);
our $VERSION   = '0.0.3';

const my $ASCII_DOLLAR_SIGN => 36;

sub create_sarif_location {
    my ($cpanfile_path) = @_;
    return [
        +{
            physicalLocation => +{
                artifactLocation => +{
                    uri => $cpanfile_path,
                },
            },
        },
    ];
}

sub format_vulnerability_as_sarif_result {
    my ( $dependency, $vulnerability, $location ) = @_;

    my $rule_id = $vulnerability -> {cve_id} // 'BUNKAI-VULN-UNKNOWN';
    my $message =
      sprintf 'Module \'%s\' has vulnerability %s: %s', $dependency -> {module}, $rule_id,
      $vulnerability -> {description};

    return +{
        ruleId    => $rule_id,
        level     => 'error',
        message   => +{ text => $message },
        locations => $location,
    };
}

sub format_unpinned_as_sarif_result {
    my ( $dependency, $location ) = @_;

    return +{
        ruleId    => 'BUNKAI-UNPINNED',
        level     => 'warning',
        message   => +{ text => "Module '$dependency -> {module}' has no version specified." },
        locations => $location,
    };
}

sub format_outdated_as_sarif_result {
    my ( $dependency, $location ) = @_;

    my $message =
      sprintf 'Module \'%s\' is outdated. Specified: %s, Latest: %s',
      $dependency -> {module}, $dependency -> {version}, $dependency -> {latest_version};

    return +{
        ruleId    => 'BUNKAI-OUTDATED',
        level     => 'warning',
        message   => +{ text => $message },
        locations => $location,
    };
}

sub map_dependency_to_sarif_results {
    my ( $dependency, $cpanfile_path ) = @_;

    my @results;
    my $location = create_sarif_location($cpanfile_path);

    if ( !$dependency -> {has_version} ) {
        push @results, format_unpinned_as_sarif_result( $dependency, $location );
    }
    elsif ( $dependency -> {is_outdated} ) {
        push @results, format_outdated_as_sarif_result( $dependency, $location );
    }

    if ( $dependency -> {has_vulnerabilities} ) {
        for my $vulnerability ( @{ $dependency -> {vulnerabilities} } ) {
            next if $vulnerability -> {type} eq 'error';
            push @results,
              format_vulnerability_as_sarif_result( $dependency, $vulnerability, $location );
        }
    }

    return @results;
}

sub generate_sarif {
    my ( $dependencies, $cpanfile_path ) = @_;

    croak q{'dependencies' must be an array reference}
      if ref $dependencies ne 'ARRAY';
    croak q{'cpanfile_path' must be a defined string}
      if !defined $cpanfile_path || !length $cpanfile_path;

    my @results =
      map { map_dependency_to_sarif_results( $_, $cpanfile_path ) } @{$dependencies};

    return +{
        chr($ASCII_DOLLAR_SIGN) . 'schema' =>
'https://raw.githubusercontent.com/oasis-tcs/sarif-spec/master/Schemata/sarif-schema-2.1.0.json',
        version => '2.1.0',
        runs    => [
            +{
                tool => +{
                    driver => +{
                        name    => 'Bunkai',
                        version => $main::VERSION,
                        informationUri =>
                          'https://github.com/gunderf/bunkai-sca-tool',
                    },
                },
                results => \@results,
            },
        ],
    };
}

1;
