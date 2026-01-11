package Bunkai::Engine::Updater;

use 5.034;
use strict;
use warnings;

use version;
use Exporter qw(import);
use Path::Tiny qw(path);

our @EXPORT_OK = qw(plan_cpanfile_updates apply_cpanfile_updates);
our $VERSION   = '0.0.4';

sub parse_version_value {
    my ($value) = @_;

    return if !defined $value;

    my $parsed_version = eval { version -> new($value) };

    return if $@;

    return $parsed_version;
}

sub extract_version_from_range {
    my ($range) = @_;

    return if !defined $range;

    if ( $range =~ m{([0-9]+(?:\.[0-9]+)*(?:_[0-9]+)?) }xms ) {
        return $1;
    }

    return;
}

sub find_fixed_version {
    my ($vulnerabilities) = @_;

    for my $vulnerability ( @{$vulnerabilities} ) {
        next if !$vulnerability -> {fixed_version};

        my $version = extract_version_from_range( $vulnerability -> {fixed_version} );
        return $version if defined $version;
    }

    return;
}

sub is_newer_version {
    my ( $current_version, $candidate_version ) = @_;

    return 1 if !defined $current_version;

    my $current_parsed  = parse_version_value($current_version);
    my $candidate_parsed = parse_version_value($candidate_version);

    return 1 if !defined $current_parsed || !defined $candidate_parsed;

    if ( $candidate_parsed > $current_parsed ) {
        return 1;
    }

    return 0;
}

sub plan_cpanfile_updates {
    my ($dependencies) = @_;

    my @updates;

    for my $dependency ( @{$dependencies} ) {
        if ( !$dependency -> {has_version} && defined $dependency -> {latest_version} ) {
            push @updates, +{
                module  => $dependency -> {module},
                version => $dependency -> {latest_version},
                reason  => 'missing_version',
            };
            next;
        }

        next if !$dependency -> {has_vulnerabilities};

        my $fixed_version = find_fixed_version( $dependency -> {vulnerabilities} );
        my $candidate_version = $fixed_version // $dependency -> {latest_version};

        next if !defined $candidate_version;
        next if !$dependency -> {has_version};
        next if !is_newer_version( $dependency -> {version}, $candidate_version );

        push @updates, +{
            module  => $dependency -> {module},
            version => $candidate_version,
            reason  => 'vulnerability_fix',
        };
    }

    return \@updates;
}

sub update_dependency_line {
    my ( $line, $versions_by_module ) = @_;

    my $line_ending = q{};
    if ( $line =~ s/(\R)\z// ) {
        $line_ending = $1;
    }

    if (
        $line =~ m{
            \A
            (\s*
                (?:requires|recommends|suggests|conflicts|test_requires|build_requires|configure_requires|author_requires)
                \s+
            )
            (['"])
            ([^'"]+)
            \2
            \s*
            (?: , | => )
            \s*
            (['"])? ([^'";\s]+) \4?
            \s*
            ;
            \s*
            \z
        }xms
      )
    {
        my ( $prefix, $quote, $module ) = ( $1, $2, $3 );
        my $new_version = $versions_by_module -> {$module};

        if ( defined $new_version ) {
            my $updated_line =
              $prefix . $quote . $module . $quote . ' => ' . $quote . $new_version . $quote . ';' . $line_ending;
            return ( $updated_line, 1 );
        }
    }

    if (
        $line =~ m{
            \A
            (\s*
                (?:requires|recommends|suggests|conflicts|test_requires|build_requires|configure_requires|author_requires)
                \s+
            )
            (['"])
            ([^'"]+)
            \2
            \s*
            ;
            \s*
            \z
        }xms
      )
    {
        my ( $prefix, $quote, $module ) = ( $1, $2, $3 );
        my $new_version = $versions_by_module -> {$module};

        if ( defined $new_version ) {
            my $updated_line =
              $prefix . $quote . $module . $quote . ' => ' . $quote . $new_version . $quote . ';' . $line_ending;
            return ( $updated_line, 1 );
        }
    }

    return ( $line . $line_ending, 0 );
}

sub apply_cpanfile_updates {
    my ( $cpanfile_path, $updates ) = @_;

    return 0 if !@{$updates};

    my %versions_by_module = map { $_ -> {module} => $_ -> {version} } @{$updates};
    my $cpanfile = path($cpanfile_path);
    my @lines = $cpanfile -> lines;
    my @updated_lines;
    my $updated = 0;

    for my $line (@lines) {
        my ( $updated_line, $changed ) = update_dependency_line( $line, \%versions_by_module );
        push @updated_lines, $updated_line;
        $updated += $changed;
    }

    if ($updated) {
        $cpanfile -> spew(@updated_lines);
    }

    return $updated;
}

1;
