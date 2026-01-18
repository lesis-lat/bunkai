package Bunkai::Component::Updater;

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

    if ( !defined $value ) {
        return;
    }

    my $parsed_version = eval { version -> new($value) };

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
        if ( !$vulnerability -> {fixed_version} ) {
            next;
        }

        my $version = extract_version_from_range( $vulnerability -> {fixed_version} );
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

        if ( !$dependency -> {has_vulnerabilities} ) {
            next;
        }

        my $fixed_version = find_fixed_version( $dependency -> {vulnerabilities} );
        my $candidate_version = $dependency -> {latest_version};

        if ( defined $fixed_version ) {
            $candidate_version = $fixed_version;
        }

        if ( !defined $candidate_version ) {
            next;
        }

        if ( !$dependency -> {has_version} ) {
            next;
        }

        if ( !is_newer_version( $dependency -> {version}, $candidate_version ) ) {
            next;
        }

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
        (?<quote>['"])
        (?<module>[^'"]+)
        \k<quote>
    }xms;
    my $version_pattern = qr{
        (?<version_quote>['"])?
        (?<version>[^'";\s]+)
        (?(<version_quote>)\k<version_quote>)
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
        (?:,|=>)
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

    if ( $line =~ $module_with_version_pattern ) {
        my $prefix = $LAST_PAREN_MATCH{prefix};
        my $quote = $LAST_PAREN_MATCH{quote};
        my $module = $LAST_PAREN_MATCH{module};
        my $new_version = $versions_by_module -> {$module};

        if ( defined $new_version ) {
            my $updated_line = sprintf q{%s%s%s%s => %s%s%s;%s},
              $prefix, $quote, $module, $quote, $quote, $new_version, $quote, $line_ending;
            return ( $updated_line, 1 );
        }
    }

    if ( $line =~ $module_without_version_pattern ) {
        my $prefix = $LAST_PAREN_MATCH{prefix};
        my $quote = $LAST_PAREN_MATCH{quote};
        my $module = $LAST_PAREN_MATCH{module};
        my $new_version = $versions_by_module -> {$module};

        if ( defined $new_version ) {
            my $updated_line = sprintf q{%s%s%s%s => %s%s%s;%s},
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
