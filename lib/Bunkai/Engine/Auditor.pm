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
use Const::Fast;

our @EXPORT_OK = qw(audit_dependencies);
our $VERSION   = '0.0.4';
const my $WAITPID_ERROR => -1;

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

    my @vulnerabilities;
    my %seen_ids;
    my @advisory_chunks = $output =~ m{
        (^\s* [*] \s+ CPANSA-[^\n]* \n .*?)
        (?= ^\s* [*] \s+ CPANSA- | \z )
    }gmsx;

    for my $chunk (@advisory_chunks) {
        my $fixed_version;
        if ( $chunk =~ m{^Fixed \s range: \s* ([[:graph:]].*)}imxs ) {
            $fixed_version = $1;
        }

        my @ids = $chunk =~ m{
            (
                CVE-[[:digit:]]{4}-[[:digit:]]+
            )
        }gmsx;
        if ( !@ids && $chunk =~ m{
            (
                CPANSA-[[:word:]-]+-[[:digit:]]+-[[:word:]]*
            )
        }xms ) {
            @ids = ($1);
        }
        if ( !@ids ) {
            @ids = ('N/A');
        }

        for my $id (@ids) {
            if ( $seen_ids{$id} ) {
                next;
            }
            $seen_ids{$id} = 1;
            push @vulnerabilities, +{
                type          => 'vulnerability',
                cve_id        => $id,
                description   => $chunk,
                fixed_version => $fixed_version,
            };
        }
    }

    if (@vulnerabilities) {
        return \@vulnerabilities;
    }

    my $fixed_version;
    if ( $output =~ m{^Fixed \s range: \s* ([[:graph:]].*)}imxs ) {
        $fixed_version = $1;
    }

    my $vulnerability_id = 'N/A';
    if ( $output =~ m{
        (
            CVE-[[:digit:]]{4}-[[:digit:]]+
        )
    }xms ) {
        $vulnerability_id = $1;
    }
    elsif ( $output =~ m{
        (
            CPANSA-[[:word:]-]+-[[:digit:]]+-[[:word:]]*
        )
    }xms ) {
        $vulnerability_id = $1;
    }

    return [
        +{
            type          => 'vulnerability',
            cve_id        => $vulnerability_id,
            description   => $output,
            fixed_version => $fixed_version,
        }
    ];
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

        my $wait_result = waitpid $process_id, 0;
        if ( $wait_result == $WAITPID_ERROR ) {
            carp "Could not wait for cpan-audit process: $OS_ERROR";
        }
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
