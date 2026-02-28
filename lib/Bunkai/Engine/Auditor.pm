package Bunkai::Engine::Auditor;

use 5.034;
use strict;
use warnings;

use English qw(-no_match_vars);
use Exporter qw(import);
use IPC::Open3 qw(open3);
use Symbol qw(gensym);
use Carp qw(carp);
use Try::Tiny;

our @EXPORT_OK = qw(audit_dependencies);
our $VERSION   = '0.0.4';

sub parse_audit_output {
    my ($output) = @_;

    if ( !defined $output ) {
        return [];
    }

    $output =~ s/\s+\z//msx;

    if ( !$output ) {
        return [];
    }

    if ( $output =~ m{Error: \s Module .*? \s is \s not \s in \s database}xms ) {
        return [ +{ type => 'error', description => $output } ];
    }

    if ( $output =~ m{No \s known \s vulnerabilities \s found}xms ) {
        return [];
    }

    my $fixed_version;
    if ( $output =~ m{^Fixed \s range: \s* (\S.*)}imxs ) {
        $fixed_version = $1;
    }

    my $vulnerability_id = 'N/A';
    my $has_cve_id = $output =~ m{(CVE-[0-9]{4}-[0-9]+)}xms;
    if ($has_cve_id) {
        $vulnerability_id = $1;
    }
    if ( !$has_cve_id && $output =~ m{(CPANSA-[[:word:]-]+-[0-9]+-[[:word:]]*)}xms ) {
        $vulnerability_id = $1;
    }

    my $vulnerability = +{
        type          => 'vulnerability',
        cve_id        => $vulnerability_id,
        description   => $output,
        fixed_version => $fixed_version,
    };

    return [$vulnerability];
}

sub find_vulnerabilities_for_module {
    my ($dependency) = @_;

    my @command = ( 'cpan-audit', 'module', $dependency -> {module} );
    if ($dependency -> {has_version}) {
        push @command, $dependency -> {version};
    }

    my $output = q{};
    my $execution_error;

    try {
        my $error_handle = gensym;
        my $process_id = open3(my $in_handle, my $out_handle, $error_handle, @command);

        close $in_handle or carp "Could not close input handle: $OS_ERROR";

        {
            local $INPUT_RECORD_SEPARATOR = undef;
            my $stdout = <$out_handle>;
            my $stderr = <$error_handle>;
            $output = ($stdout // q{}) . ($stderr // q{});
        }

        waitpid $process_id, 0;
    }
    catch {
        $execution_error = $_;
    };

    if ( defined $execution_error ) {
        chomp $execution_error;
        return [
            +{
                type => 'error',
                description =>
                  "Error: Failed to execute cpan-audit for module '$dependency->{module}': $execution_error",
            }
        ];
    }

    return parse_audit_output($output);
}

sub enrich_with_vulnerabilities {
    my ($dependency) = @_;

    my $vulnerabilities = find_vulnerabilities_for_module($dependency);

    return +{
        %{$dependency},
        vulnerabilities     => $vulnerabilities,
        has_vulnerabilities => @{$vulnerabilities} > 0,
    };
}

sub audit_dependencies {
    my ($dependencies) = @_;

    return [ map { enrich_with_vulnerabilities($_) } @{$dependencies} ];
}

1;
