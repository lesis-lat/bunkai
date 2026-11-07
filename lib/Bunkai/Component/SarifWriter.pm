package Bunkai::Component::SarifWriter;

use 5.034;
use strict;
use warnings;

use Carp     qw(croak);
use English  qw(-no_match_vars);
use Exporter qw(import);
use JSON::PP;

use Bunkai::Utils::Sarif qw(generate_sarif);
use Type::Params         qw(signature);
use Types::Standard      qw(Str);

use Bunkai::Types qw(DependencyList);

our @EXPORT_OK = qw(write_sarif_report);
our $VERSION   = '0.0.4';

my $write_sarif_report_check =
  signature(positional => [DependencyList, Str, Str]);

sub write_sarif_report {
    my ($dependencies, $cpanfile_path, $output_file) = @_;

    ($dependencies, $cpanfile_path, $output_file) =
      $write_sarif_report_check ->($dependencies, $cpanfile_path,
        $output_file);

    my $sarif_data = generate_sarif($dependencies, $cpanfile_path);
    my $json       = JSON::PP -> new -> pretty -> encode($sarif_data);

    open my $fh, '>', $output_file
      or croak "Cannot open SARIF output file '$output_file': $OS_ERROR";
    print {$fh} $json
      or croak "Cannot write to SARIF output file '$output_file': $OS_ERROR";
    close $fh
      or croak "Cannot close SARIF output file '$output_file': $OS_ERROR";

    return;
}

1;
