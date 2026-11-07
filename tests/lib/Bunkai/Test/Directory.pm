package Bunkai::Test::Directory;

use strict;
use warnings;

use Carp       qw(croak);
use English    qw(-no_match_vars);
use File::Path qw(remove_tree);
use File::Spec;
use Readonly;
use Time::HiRes qw(gettimeofday);

our $VERSION = '0.0.1';

Readonly my $ENTROPY_BYTES    => 8;
Readonly my $DIRECTORY_MODE   => oct '0700';
Readonly my $MAXIMUM_ATTEMPTS => 32;

my @created;
my $counter = 0;

sub _entropy {
    my $handle;

    if (open $handle, '<', '/dev/urandom') {
        my $bytes = q{};
        my $read  = read $handle, $bytes, $ENTROPY_BYTES;

        close $handle or croak 'cannot close the entropy source';

        if ($read) {
            return unpack 'H*', $bytes;
        }
    }

    my ($seconds, $microseconds) = gettimeofday();
    $counter = $counter + 1;

    return sprintf '%x%x%x', $seconds, $microseconds, $counter;
}

sub new {
    my ($self, %options) = @_;

    my $base = $options{base} || File::Spec -> tmpdir();

    for my $attempt (1 .. $MAXIMUM_ATTEMPTS) {
        my $path = File::Spec -> catdir($base,
            'bunkai-test-' . $PROCESS_ID . q{-} . _entropy());

        if (mkdir $path, $DIRECTORY_MODE) {
            push @created, $path;

            return $path;
        }
    }

    croak "cannot create a private directory under $base";
}

sub remove {
    my ($self, $path) = @_;

    @created = grep { $_ ne $path } @created;

    remove_tree($path);

    return;
}

END {
    for my $path (@created) {
        remove_tree($path);
    }

    @created = ();
}

1;
