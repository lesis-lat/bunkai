package Bunkai::Engine::Updater;

use 5.034;
use strict;
use warnings;

use English qw(-no_match_vars);
use version;
use Exporter qw(import);
use Path::Tiny qw(path);

our @EXPORT_OK = qw(
  plan_issue_updates
  plan_single_update_by_issue_id
  plan_cpanfile_updates
  apply_cpanfile_updates
);
our $VERSION   = '0.0.4';

sub parse_version_value {
    my ($value) = @_;

    if ( !defined $value ) {
        return;
    }

    my $parsed_version = eval { version->new($value) };

    if ( !defined $parsed_version ) {
        return;
    }

    return $parsed_version;
}

sub extract_version_from_range {
    my ($range) = @_;

    if ( !defined $range ) {
        return;
    }

    if ( $range =~ m{([[:digit:]]+(?:[.][[:digit:]]+)*(?:_[[:digit:]]+)?)}xms ) {
        return $1;
    }

    return;
}

sub find_fixed_version {
    my ($vulnerabilities) = @_;

    for my $vulnerability ( @{$vulnerabilities} ) {
        if ( !$vulnerability->{fixed_version} ) {
            next;
        }

        my $version = extract_version_from_range( $vulnerability->{fixed_version} );
        if ( defined $version ) {
            return $version;
        }
    }

    return;
}

sub is_newer_version {
    my ( $current_version, $candidate_version ) = @_;

    if ( !defined $current_version ) {
        return 1;
    }

    my $current_parsed  = parse_version_value($current_version);
    my $candidate_parsed = parse_version_value($candidate_version);

    if ( !defined $current_parsed || !defined $candidate_parsed ) {
        return 1;
    }

    if ( $candidate_parsed > $current_parsed ) {
        return 1;
    }

    return 0;
}

sub sanitize_issue_fragment {
    my ($value) = @_;

    my $fragment = $value // q{unknown};
    $fragment =~ s{ [[:^alnum:]]+ }{-}xmsg;
    $fragment =~ s{ \A [-]+ | [-]+ \z }{}xmsg;

    if ( !length $fragment ) {
        return q{unknown};
    }

    return lc $fragment;
}

sub build_issue_id {
    my ( $reason, $module, $advisory_id ) = @_;

    my @parts = (
        sanitize_issue_fragment($reason),
        sanitize_issue_fragment($module),
    );

    if ( defined $advisory_id && length $advisory_id ) {
        push @parts, sanitize_issue_fragment($advisory_id);
    }

    return join q{-}, @parts;
}

sub plan_issue_updates {
    my ($dependencies) = @_;

    my @issues;

    for my $dependency ( @{$dependencies} ) {
        my $module = $dependency->{module};
        my $current_version = $dependency->{version};
        my $latest_version = $dependency->{latest_version};

        if ( !$dependency->{has_version} && defined $latest_version ) {
            my $reason = 'missing_version';
            push @issues, +{
                id              => build_issue_id( $reason, $module, undef ),
                module          => $module,
                current_version => undef,
                target_version  => $latest_version,
                reason          => $reason,
                advisory_id     => undef,
            };
        }

        if (
            $dependency->{has_version}
            && $dependency->{is_outdated}
            && defined $latest_version
            && is_newer_version( $current_version, $latest_version )
          )
        {
            my $reason = 'outdated';
            push @issues, +{
                id              => build_issue_id( $reason, $module, undef ),
                module          => $module,
                current_version => $current_version,
                target_version  => $latest_version,
                reason          => $reason,
                advisory_id     => undef,
            };
        }

        if ( !$dependency->{has_vulnerabilities} || !$dependency->{has_version} ) {
            next;
        }

        for my $vulnerability ( @{ $dependency->{vulnerabilities} } ) {
            if ( ( $vulnerability->{type} // q{} ) eq 'error' ) {
                next;
            }

            my $fixed_version = extract_version_from_range( $vulnerability->{fixed_version} );
            my $candidate_version = $fixed_version // $latest_version;
            if ( !defined $candidate_version ) {
                next;
            }

            if ( !is_newer_version( $current_version, $candidate_version ) ) {
                next;
            }

            my $advisory_id = $vulnerability->{cve_id};
            if ( !defined $advisory_id || !length $advisory_id ) {
                $advisory_id = 'BUNKAI-VULN-UNKNOWN';
            }

            my $reason = 'vulnerability_fix';
            push @issues, +{
                id              => build_issue_id( $reason, $module, $advisory_id ),
                module          => $module,
                current_version => $current_version,
                target_version  => $candidate_version,
                reason          => $reason,
                advisory_id     => $advisory_id,
            };
        }
    }

    return \@issues;
}

sub plan_cpanfile_updates {
    my ($dependencies) = @_;

    my $issues = plan_issue_updates($dependencies);
    my %best_update_by_module;

    for my $issue ( @{$issues} ) {
        my $module = $issue->{module};
        my $target_version = $issue->{target_version};

        my $existing_update = $best_update_by_module{$module};
        if ( !defined $existing_update
            || is_newer_version( $existing_update->{version}, $target_version ) )
        {
            $best_update_by_module{$module} = +{
                module  => $module,
                version => $target_version,
                reason  => $issue->{reason},
            };
        }
    }

    return [
        map { $best_update_by_module{$_} }
          sort keys %best_update_by_module
    ];
}

sub plan_single_update_by_issue_id {
    my ( $dependencies, $issue_id ) = @_;

    my $issues = plan_issue_updates($dependencies);
    my ($matched_issue) = grep { $_->{id} eq $issue_id } @{$issues};

    if ( !defined $matched_issue ) {
        return;
    }

    my @updates;

    push @updates, +{
        module  => $matched_issue->{module},
        version => $matched_issue->{target_version},
        reason  => $matched_issue->{reason},
    };

    return \@updates;
}

sub update_dependency_line {
    my ( $line, $versions_by_module ) = @_;

    my $line_ending = q{};
    if ( $line =~ s/(\R)\z//xms ) {
        $line_ending = $1;
    }

    my @requirement_keywords = qw(
      requires
      recommends
      suggests
      conflicts
      test_requires
      build_requires
      configure_requires
      author_requires
    );
    my $requirement_keywords = qr{(?:@{[ join q{|}, @requirement_keywords ]})}xms;
    my $statement_prefix_pattern = qr{
        (?<prefix>\s*$requirement_keywords\s+)
    }xms;
    my $quoted_module_pattern = qr{
        (['"])
        ([^'"]+)
        (?:['"])
    }xms;
    my $version_pattern = qr{
        (?:['"])?
        ([^'";\s]+)
        (?:['"])?
    }xms;
    my $statement_end_pattern = qr{
        \s*
        ;
        \s*
        \z
    }xms;
    my $module_with_version_pattern = qr{
        \A
        $statement_prefix_pattern
        $quoted_module_pattern
        \s*
        (,|=>)
        \s*
        $version_pattern
        $statement_end_pattern
    }xms;
    my $module_without_version_pattern = qr{
        \A
        $statement_prefix_pattern
        $quoted_module_pattern
        $statement_end_pattern
    }xms;

    if ( my @captures = $line =~ $module_with_version_pattern ) {
        my ( $prefix, $quote, $module, $separator, @unused ) = @captures;
        my $new_version = $versions_by_module->{$module};

        if ( defined $new_version ) {
            my $updated_line = sprintf q{%s%s%s%s%s %s%s%s;%s},
              $prefix,
              $quote,
              $module,
              $quote,
              $separator,
              $quote,
              $new_version,
              $quote,
              $line_ending;
            return ( $updated_line, 1 );
        }
    }

    if ( my @captures = $line =~ $module_without_version_pattern ) {
        my ( $prefix, $quote, $module ) = @captures[ 0 .. 2 ];
        my $new_version = $versions_by_module->{$module};

        if ( defined $new_version ) {
            my $updated_line = sprintf q{%s%s%s%s, %s%s%s;%s},
              $prefix, $quote, $module, $quote, $quote, $new_version, $quote, $line_ending;
            return ( $updated_line, 1 );
        }
    }

    return ( $line . $line_ending, 0 );
}

sub apply_cpanfile_updates {
    my ( $cpanfile_path, $updates ) = @_;

    if ( !@{$updates} ) {
        return 0;
    }

    my %versions_by_module = map { $_->{module} => $_->{version} } @{$updates};
    my $cpanfile = path($cpanfile_path);
    my @lines = $cpanfile->lines;
    my @updated_lines;
    my $updated = 0;

    for my $line (@lines) {
        my ( $updated_line, $changed ) = update_dependency_line( $line, \%versions_by_module );
        push @updated_lines, $updated_line;
        $updated += $changed;
    }

    if ($updated) {
        $cpanfile->spew(@updated_lines);
    }

    return $updated;
}

1;
