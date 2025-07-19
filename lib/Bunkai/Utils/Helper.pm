package Bunkai::Utils::Helper;

use 5.034;
use strict;
use warnings;

use Const::Fast;
use Exporter qw(import);

our $VERSION   = '0.0.3';
our @EXPORT_OK = qw(get_interface_info);

const my $INTERFACE_INFO => <<'END_INFO';

Bunkai v0.0.3
SCA for Perl Projects
=====================
    Command          Description
    -------          -----------
    -p, --path=PATH      Path to the project containing a cpanfile
    -s, --sarif[=FILE]   Output results to a SARIF file (default: bunkai_results.sarif)
    -h, --help           Display this help menu

END_INFO

sub get_interface_info {
    return $INTERFACE_INFO;
}

1;
