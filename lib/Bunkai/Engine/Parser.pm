package Bunkai::Engine::Parser;

use 5.034;
use strict;
use warnings;

use Exporter qw(import);
use Module::CPANfile;
use Path::Tiny qw(path);

our @EXPORT_OK = qw(parse_cpanfile);

our $VERSION = '0.0.4';

sub parse_cpanfile {
    my ($project_path) = @_;
    my $cpanfile_path = path($project_path)->child('cpanfile');

    if ( !-f $cpanfile_path ) {
        return +{
            success       => 0,
            reason        => 'cpanfile_not_found',
            data          => [],
            cpanfile_path => $cpanfile_path->stringify
        };
    }

    my $cpanfile     = Module::CPANfile->load($cpanfile_path);
    my $requirements = $cpanfile->prereqs->merged_requirements;
    my $module_hash  = $requirements->as_string_hash;

    my @dependencies;
    foreach my $module ( sort keys %{$module_hash} ) {
        my $version = $module_hash->{$module};

        $version =~ s{
            \A \s*
            (?:==|>=|<=|[<>])
            \s*
        }{}xms;

        my $module_version;
        my $has_version = 0;
        if ( $version ne '0' ) {
            $module_version = $version;
            $has_version = 1;
        }

        push @dependencies, +{
            module      => $module,
            version     => $module_version,
            has_version => $has_version,
        };
    }

    return +{
        success       => 1,
        data          => \@dependencies,
        cpanfile_path => $cpanfile_path->stringify
    };
}

1;
