package Bunkai::Engine::Auditor;

use 5.034;
use strict;
use warnings;

use Exporter qw(import);
use Bunkai::Utils::VDB qw(get_vulnerabilities);

our @EXPORT_OK = qw(audit_dependencies);
our $VERSION   = '0.0.3';

sub enrich_with_vulnerabilities {
    my ($dependency) = @_;

    my $vulnerabilities = get_vulnerabilities(
        $dependency->{module},
        $dependency->{version}
    );

    return +{
        %{$dependency},
        vulnerabilities => $vulnerabilities,
        has_vulnerabilities => @{$vulnerabilities} > 0,
    };
}

sub audit_dependencies {
    my ($dependencies) = @_;

    return [ map { enrich_with_vulnerabilities($_) } @{$dependencies} ];
}

1;
