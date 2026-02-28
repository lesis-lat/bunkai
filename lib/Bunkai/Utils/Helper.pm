package Bunkai::Utils::Helper;

use 5.034;
use strict;
use warnings;

use Const::Fast;
use Exporter qw(import);

our $VERSION   = '0.0.4';
our @EXPORT_OK = qw(get_interface_info);

const my $INTERFACE_INFO => <<'END_INFO';

Bunkai v0.0.4
SCA for Perl Projects
=====================
    Command          Description
    -------          -----------
    -p, --path=PATH      Path to the project containing a cpanfile
    -s, --sarif[=FILE]   Output results to a SARIF file (default: bunkai_results.sarif)
    -u, --update-cpanfile   Update cpanfile with latest or fixed dependency versions
    -P, --plan-updates[=FILE]   Write issue-scoped cpanfile updates to JSON (default: bunkai_updates.json)
        --apply-update-id=ID    Apply a single issue-scoped update by ID
    -h, --help           Display this help menu

END_INFO

sub get_interface_info {
    return $INTERFACE_INFO;
}

1;
