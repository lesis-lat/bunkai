package Bunkai::Utils::VDB;

use 5.034;
use strict;
use warnings;

use Readonly;
Readonly my $CACHE_TTL => 24 * 60 * 60;

use Exporter qw(import);
use HTTP::Tiny;
use JSON::PP;
use Path::Tiny qw(path);
use Time::HiRes qw(time);

our @EXPORT_OK = qw(update_vdb get_vulnerabilities);
our $VERSION   = '0.0.3';

sub fetch_cve_data {
    my $http     = HTTP::Tiny->new( timeout => 30 );
    my $response = $http->get('https://cve.mitre.org/cgi-bin/cvekey.cgi?keyword=perl');

    if ( !$response->{success} ) {
        return;
    }
    return $response->{content};
}

sub parse_cve_html {
    my ($html_content) = @_;

    my $count_pattern = qr{There \s are \s <b>(\d+)</b> \s CVE \s Records}msx;
    my ($total_count) = $html_content =~ m{$count_pattern}msx;
    if ( !$total_count ) {
        return [];
    }

    my @vulnerabilities;

    my $cve_id_regex      = qr{ (CVE-\d{4}-\d+) }xms;
    my $description_regex = qr{ (.*?) }xms;
    my $table_row_start   = qr{ <tr> \s* }xms;
    my $table_row_end     = qr{ </tr> }xms;
    my $cve_id_cell       = qr{ <td[^>]*> <a[^>]*> $cve_id_regex </a> </td> \s* }xms;
    my $desc_cell         = qr{ <td[^>]*> $description_regex </td> \s* }xms;
    my $cve_row_regex     = qr{ $table_row_start $cve_id_cell $desc_cell $table_row_end }xms;

    while ( $html_content =~ m{$cve_row_regex}gmsx ) {
        my ( $cve_id, $description ) = ( $1, $2 );

        $description =~ s{<[^>]*>}{}gmsx;
        $description =~ s{\s+}{ }gmsx;
        $description =~ s{^\s+|\s+$}{}gmsx;

        my $module_name  = extract_module_name($description);
        my $version_info = extract_version_info($description);

        if ( !$module_name ) {
            next;
        }

        push @vulnerabilities, +{
            cve_id      => $cve_id,
            module      => $module_name,
            description => $description,
            %{$version_info},
        };
    }

    return \@vulnerabilities;
}

sub extract_module_name {
    my ($description) = @_;

    my ($module_name);

    my @extraction_patterns = (
        qr{^(\w+(?:::\w+)*)\s+versions?\s+}msx,
        qr{^(\w+(?:::\w+)*)}msx,
        qr{(\w+(?:::\w+)*)\s+.*?\s+for\s+Perl}msx,
        qr{Perl\s+(\w+(?:::\w+)*)}msx,
    );

    for my $pattern (@extraction_patterns) {
        ($module_name) = $description =~ $pattern;
        return $module_name if $module_name;
    }

    return;
}

sub extract_version_info {
    my ($description) = @_;

    my %version_info = (
        affected_versions => [],
        fixed_version     => undef,
    );

    my @version_patterns = (
        {
            pattern => qr{before\s+version\s+(v?[\d.]+)}msx,
            handler => sub {
                my ($match) = @_;
                $version_info{fixed_version} = $match;
            },
        },
        {
            pattern => qr{versions?\s+(v?[\d.]+)\s+through\s+(v?[\d.]+)}msx,
            handler => sub {
                my ($from, $to) = @_;
                $version_info{version_range} = { from => $from, to => $to };
            },
        },
        {
            pattern => qr{(\w+(?:::\w+)*)\s+version\s+(v?[\d.]+)}msx,
            handler => sub {
                my ($module, $version) = @_;
                push @{ $version_info{affected_versions} }, $version;
            },
        },
        {
            pattern => qr{version\s+(v?[\d.]+)}msx,
            handler => sub {
                my ($version) = @_;
                push @{ $version_info{affected_versions} }, $version;
            },
        },
    );

    for my $pattern_config (@version_patterns) {
        my @matches = $description =~ $pattern_config->{pattern};
        if (@matches) {
            $pattern_config->{handler}->(@matches);
            last;
        }
    }

    return \%version_info;
}

sub load_vdb_cache {
    my $vdb_path = path('data/vdb.json');
    if ( !-f $vdb_path ) {
        return +{ last_updated => 0, vulnerabilities => [] };
    }

    my $json_content = $vdb_path->slurp_utf8;
    return JSON::PP->new->decode($json_content);
}

sub save_vdb_cache {
    my ($vdb_data) = @_;

    my $data_dir = path('data');
    if ( !-d $data_dir ) {
        $data_dir->mkpath;
    }

    my $vdb_path     = $data_dir->child('vdb.json');
    my $json_content = JSON::PP->new->pretty->encode($vdb_data);

    $vdb_path->spew_utf8($json_content);
    return;
}

sub needs_update {
    my ($vdb_data) = @_;
    my $current_time = time;
    my $cache_age    = $current_time - $vdb_data->{last_updated};

    return $cache_age > $CACHE_TTL;
}

sub update_vdb {
    my $vdb_data = load_vdb_cache();

    if ( !needs_update($vdb_data) ) {
        return $vdb_data;
    }

    my $html_content = fetch_cve_data();
    if ( !$html_content ) {
        return $vdb_data;
    }

    my $vulnerabilities = parse_cve_html($html_content);
    if ( !@{ $vulnerabilities } ) {
        return $vdb_data;
    }

    my $updated_vdb = +{
        last_updated    => time,
        vulnerabilities => $vulnerabilities,
    };

    save_vdb_cache($updated_vdb);
    return $updated_vdb;
}

sub get_vulnerabilities {
    my ( $module_name, $version ) = @_;

    my $vdb_data       = update_vdb();
    my @matching_vulns = ();

    for my $vuln ( @{ $vdb_data->{vulnerabilities} } ) {
        my $vuln_module = $vuln->{module};

        if ( $vuln_module eq $module_name ) {
            if ( is_version_affected( $version, $vuln ) ) {
                push @matching_vulns, $vuln;
            }
            next;
        }

        if ( _modules_match( $vuln_module, $module_name ) ) {
            if ( is_version_affected( $version, $vuln ) ) {
                push @matching_vulns, $vuln;
            }
        }
    }

    return \@matching_vulns;
}

sub _modules_match {
    my ( $vuln_module, $target_module ) = @_;

    if ( $target_module eq 'YAML::LibYAML' && $vuln_module eq 'YAML' ) {
        return 1;
    }

    return 0;
}

sub is_version_affected {
    my ( $version, $vuln ) = @_;

    if ( !defined $version ) {
        return 1;
    }

    my $normalized_version = $version;
    $normalized_version =~ s{^v}{}msx;

    if ( $vuln->{affected_versions} && @{ $vuln->{affected_versions} } ) {
        for my $affected_version ( @{ $vuln->{affected_versions} } ) {
            my $normalized_affected = $affected_version;
            $normalized_affected =~ s{^v}{}msx;
            return 1 if $normalized_version eq $normalized_affected;
        }
    }

    if ( $vuln->{version_range} ) {
        my $range           = $vuln->{version_range};
        my $normalized_from = $range->{from};
        my $normalized_to   = $range->{to};
        $normalized_from =~ s{^v}{}msx;
        $normalized_to =~ s{^v}{}msx;
        return version_in_range( $normalized_version, $normalized_from, $normalized_to );
    }

    if ( $vuln->{fixed_version} ) {
        my $normalized_fixed = $vuln->{fixed_version};
        $normalized_fixed =~ s{^v}{}msx;
        return version_compare( $normalized_version, $normalized_fixed ) < 0;
    }

    if (    exists $vuln->{affected_versions}
        && @{ $vuln->{affected_versions} } == 0
        && !$vuln->{fixed_version}
        && !$vuln->{version_range} )
    {
        my $desc = $vuln->{description} || q{};
        if ( $desc =~ m{prior\s+to\s+(?:version\s+)?(v?[\d.]+)}msx ) {
            my $threshold_version = $1;
            $threshold_version =~ s{^v}{}msx;
            return version_compare( $normalized_version, $threshold_version ) < 0;
        }
        return 1;
    }

    return 0;
}

sub version_in_range {
    my ( $version, $from, $to ) = @_;

    return (
        version_compare( $version, $from ) >= 0
        && version_compare( $version, $to ) <= 0
    );
}

sub version_compare {
    my ( $v1, $v2 ) = @_;

    my @parts1 = split qr{[.]}msx, $v1;
    my @parts2 = split qr{[.]}msx, $v2;

    my $max_parts = @parts1 > @parts2 ? @parts1 : @parts2;

    for my $i ( 0 .. $max_parts - 1 ) {
        my $part1 = $parts1[$i] // 0;
        my $part2 = $parts2[$i] // 0;

        my $cmp = $part1 <=> $part2;
        return $cmp if $cmp != 0;
    }

    return 0;
}

1;
