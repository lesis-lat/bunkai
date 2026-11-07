#!/usr/bin/env perl

package main;

use 5.034;
use strict;
use warnings;

use Test::More;
use FindBin;
use lib "$FindBin::Bin/../../lib";
use lib "$FindBin::Bin/../lib";
use File::Temp                qw(tempdir);
use Path::Tiny                qw(path);
use Bunkai::Component::Parser qw(parse_cpanfile);
use Bunkai::Types             qw(ParserResult);

our $VERSION = '0.0.4';

sub build_project {
    my ($contents) = @_;

    my $directory = tempdir(CLEANUP => 1);
    path($directory) -> child('cpanfile') -> spew_raw($contents);

    return $directory;
}

sub dependency {
    my ($module, $version) = @_;

    if (defined $version) {
        return +{module => $module, version => $version, has_version => 1};
    }

    return +{module => $module, version => undef, has_version => 0};
}

my @ACCEPTED_CASES = (
    +{
        name     => 'double quoted strings without interpolation',
        cpanfile => qq{requires "Double::Quoted", "1.0";\n},
        expected => [dependency('Double::Quoted', '1.0')],
    },
    +{
        name     => 'a fat comma between module and version',
        cpanfile => "requires 'Fat::Comma' => '2.0';\n",
        expected => [dependency('Fat::Comma', '2.0')],
    },
    +{
        name     => 'a parenthesised statement',
        cpanfile => "requires('Parenthesised', '1.5');\n",
        expected => [dependency('Parenthesised', '1.5')],
    },
    +{
        name     => 'a trailing comma',
        cpanfile => "requires 'Trailing', '1.0',;\n",
        expected => [dependency('Trailing', '1.0')],
    },
    +{
        name     => 'a trailing comma inside parentheses',
        cpanfile => "requires('Trailing', '1.0',);\n",
        expected => [dependency('Trailing', '1.0')],
    },
    +{
        name     => 'empty statements',
        cpanfile => ";;requires 'Empty::Statements';;\n",
        expected => [dependency('Empty::Statements')],
    },
    +{
        name     => 'a final statement without a semicolon',
        cpanfile => q{requires 'No::Semicolon'},
        expected => [dependency('No::Semicolon')],
    },
    +{
        name     => 'a block ending without a semicolon',
        cpanfile => "on test => sub { requires 'Block::End' };\n",
        expected => [dependency('Block::End')],
    },
    +{
        name     => 'comments around statements',
        cpanfile =>
          "requires 'Commented', '1.0'; # pinned\n# requires 'Ignored';\n",
        expected => [dependency('Commented', '1.0')],
    },
    +{
        name     => 'a hash sign inside a quoted string',
        cpanfile =>
          "requires 'Hash::Inside', '1.0', url => 'https://x/#a';\n",
        expected => [dependency('Hash::Inside', '1.0')],
    },
    +{
        name     => 'a __DATA__ marker',
        cpanfile =>
          "requires 'Before::Data';\n__DATA__\nrequires 'After::Data';\n",
        expected => [dependency('Before::Data')],
    },
    +{
        name     => 'an __END__ marker followed by arbitrary text',
        cpanfile => "requires 'Before::End';\n__END__\n"
          . "system 'touch x'; `id`; ((( '''\n",
        expected => [dependency('Before::End')],
    },
    +{
        name     => 'CRLF line endings',
        cpanfile =>
          "requires 'Crlf::One', '1.0';\r\nrequires 'Crlf::Two';\r\n",
        expected => [dependency('Crlf::One', '1.0'), dependency('Crlf::Two')],
    },
    +{
        name     => 'numeric versions normalised like perl',
        cpanfile => join(q{},
            "requires 'Trailing::Zero', 1.10;\n",
            "requires 'Underscore', 1_000;\n",
            "requires 'Integer', 2;\n",
            "requires 'Leading::Zero', 5.034;\n",
        ),
        expected => [
            dependency('Integer',        '2'),
            dependency('Leading::Zero',  '5.034'),
            dependency('Trailing::Zero', '1.1'),
            dependency('Underscore',     '1000'),
        ],
    },
    +{
        name     => 'quoted and bare v-strings',
        cpanfile =>
          "requires 'Quoted::Vstring', 'v1.2.3';\nrequires 'Bare', v1.2.3;\n",
        expected => [
            dependency('Bare',            'v1.2.3'),
            dependency('Quoted::Vstring', 'v1.2.3'),
        ],
    },
    +{
        name     => 'escaped quotes and backslashes in single quotes',
        cpanfile => "requires 'Escapes', '1', note => 'a\\\\b \\'c\\'';\n",
        expected => [dependency('Escapes', '1')],
    },
    +{
        name     => 'options without a version',
        cpanfile => "requires 'Options::Only', dist => 'X/Y-1.0.tar.gz';\n",
        expected => [dependency('Options::Only')],
    },
    +{
        name     => 'a later declaration replacing an earlier one',
        cpanfile =>
          "requires 'Repeated', '1.0';\nrequires 'Repeated', '2.0';\n",
        expected => [dependency('Repeated', '2.0')],
    },
    +{
        name     => 'minimum versions merged across phases',
        cpanfile => "requires 'Merged', '1.0';\n"
          . "on test => sub { requires 'Merged', '2.0' };\n",
        expected => [dependency('Merged', '2.0')],
    },
    +{
        name     => 'version operators stripped from the requirement',
        cpanfile => join(q{},
            "requires 'Exact', '== 1.0';\n",
            "requires 'Minimum', '>= 2.0';\n",
            "requires 'Below', '< 3.0';\n",
        ),
        expected => [
            dependency('Below',   '3.0'),
            dependency('Exact',   '1.0'),
            dependency('Minimum', '2.0'),
        ],
    },
    +{
        name     => 'phases that are not merged',
        cpanfile => join(q{},
            "on develop => sub { requires 'Develop' };\n",
            "on configure => sub { requires 'Configure' };\n",
            "author_requires 'Author';\n",
            "configure_requires 'Configure::Shortcut';\n",
            "on 'x_custom' => sub { requires 'Custom' };\n",
            "on bogus => sub { requires 'Bogus' };\n",
        ),
        expected => [],
    },
    +{
        name     => 'suggests and conflicts',
        cpanfile =>
          "suggests 'Suggested';\nconflicts 'Conflicting', '< 1.0';\n",
        expected => [],
    },
    +{
        name     => 'prerequisites declared inside features',
        cpanfile => join(q{},
            "feature 'with_description', 'Description', sub {\n",
            "    requires 'Feature::Dependency';\n",
            "};\n",
            "feature(short => sub { requires 'Short::Feature' });\n",
        ),
        expected => [],
    },
    +{
        name     => 'nested phases resolved to the innermost one',
        cpanfile => join(q{},
            "on develop => sub {\n",
            "    on test => sub { requires 'Nested::Test' };\n",
            "    test_requires 'Shortcut::Inside::Develop';\n",
            "    requires 'Develop::Only';\n",
            "};\n",
        ),
        expected => [
            dependency('Nested::Test'),
            dependency('Shortcut::Inside::Develop'),
        ],
    },
    +{
        name     => 'mirror statements',
        cpanfile => join(q{},
            "mirror 'https://cpan.example.org';\n",
            "mirror('https://other.example.org');\n",
            "requires 'After::Mirror';\n",
        ),
        expected => [dependency('After::Mirror')],
    },
    +{
        name     => 'build requirements and recommendations',
        cpanfile => "build_requires 'Build', '1';\n"
          . "on build => sub { recommends 'Build::Recommended' };\n",
        expected =>
          [dependency('Build', '1'), dependency('Build::Recommended')],
    },
    +{
        name     => 'the perl interpreter requirement',
        cpanfile => "requires 'perl', '5.034';\n",
        expected => [dependency('perl', '5.034')],
    },
);

my @REJECTED_CASES = (
    +{
        name     => 'an unterminated single quoted string',
        cpanfile => "requires 'Open;\n",
        error    => qr{\A line [ ] 1: [ ] unsupported [ ] character}xms,
    },
    +{
        name     => 'an interpolated double quoted string',
        cpanfile => qq{requires "\$module";\n},
        error    => qr{\A line [ ] 1: [ ] unsupported [ ] character}xms,
    },
    +{
        name     => 'an escape inside a double quoted string',
        cpanfile => "requires \"Escaped\\n\";\n",
        error    => qr{\A line [ ] 1: [ ] unsupported [ ] character}xms,
    },
    +{
        name     => 'a bareword module name',
        cpanfile => "requires Bare::Word;\n",
        error => qr{\A line [ ] 1: [ ] unsupported [ ] character [ ] ':'}xms,
    },
    +{
        name     => 'a single word bareword module name',
        cpanfile => "requires Bareword;\n",
        error    => qr{\A line [ ] 1: [ ] expected [ ] a [ ] quoted}xms,
    },
    +{
        name     => 'a missing semicolon between statements',
        cpanfile => "requires 'First'\nrequires 'Second';\n",
        error    => qr{\A line [ ] 2: [ ] expected [ ] ',' [ ] or [ ] ';'}xms,
    },
    +{
        name     => 'an unclosed block',
        cpanfile => "on test => sub {\n    requires 'Inside';\n",
        error    => qr{\A line [ ] 3: .* end [ ] of [ ] file \z}xms,
    },
    +{
        name     => 'a block without sub',
        cpanfile => "on test => { requires 'Inside' };\n",
        error    => qr{\A line [ ] 1: [ ] expected [ ] 'sub'}xms,
    },
    +{
        name     => 'a statement without arguments',
        cpanfile => "requires;\n",
        error    => qr{\A line [ ] 1: [ ] expected [ ] a [ ] quoted}xms,
    },
    +{
        name     => 'an empty module name',
        cpanfile => "requires '';\n",
        error    => qr{\A line [ ] 1: [ ] module [ ] name}xms,
    },
    +{
        name     => 'the unimplemented osname statement',
        cpanfile => "osname 'linux';\n",
        error    => qr{\A line [ ] 1: [ ] unsupported [ ] statement}xms,
    },
    +{
        name     => 'an unknown keyword',
        cpanfile => "require 'Typo';\n",
        error    => qr{\A line [ ] 1: [ ] unsupported [ ] statement}xms,
    },
    +{
        name     => 'an unclosed parenthesis',
        cpanfile => "requires('Open', '1';\n",
        error => qr{\A line [ ] 1: [ ] expected [ ] ',' [ ] or [ ] '[)]'}xms,
    },
    +{
        name     => 'a mirror with two arguments',
        cpanfile => "mirror 'https://a', 'https://b';\n",
        error    => qr{\A line [ ] 1: [ ] expected [ ] ';'}xms,
    },
    +{
        name     => 'an exponent in a version',
        cpanfile => "requires 'Exponent', 1e5;\n",
        error    => qr{\A line [ ] 1: [ ] expected [ ] ','}xms,
    },
    +{
        name     => 'a heredoc',
        cpanfile => "requires <<MODULE;\nHeredoc\nMODULE\n",
        error    => qr{\A line [ ] 1: [ ] unsupported [ ] character}xms,
    },
    +{
        name     => 'a q{} quoted string',
        cpanfile => "requires q{Quoted};\n",
        error    => qr{\A line [ ] 1: [ ] expected [ ] a [ ] quoted}xms,
    },
    +{
        name     => 'a statement after a block without a semicolon',
        cpanfile => "on test => sub { requires 'A' } requires 'B';\n",
        error    => qr{\A line [ ] 1: [ ] expected [ ] ';'}xms,
    },
    +{
        name     => 'a feature without a block',
        cpanfile => "feature 'name', 'description';\n",
        error    => qr{\A line [ ] 1: [ ] expected [ ] ','}xms,
    },
    +{
        name     => 'a leading comma',
        cpanfile => "requires , 'A';\n",
        error    => qr{\A line [ ] 1: [ ] expected [ ] a [ ] quoted}xms,
    },
    +{
        name     => 'a stray closing brace',
        cpanfile => "requires 'A'; }\n",
        error    => qr{\A line [ ] 1: [ ] expected [ ] a [ ] cpanfile}xms,
    },
    +{
        name     => 'a negative version',
        cpanfile => "requires 'A', -1;\n",
        error    => qr{\A line [ ] 1: [ ] unsupported [ ] character}xms,
    },
    +{
        name     => 'a phase bareword without a fat comma',
        cpanfile => "on test, sub { requires 'A' };\n",
        error    => qr{\A line [ ] 1: [ ] expected [ ] a [ ] quoted}xms,
    },
    +{
        name     => 'an expression counted after multi-line strings',
        cpanfile => "# header\nrequires 'A',\n    '1.0';\n\n"
          . "requires 'B' . 'C';\n",
        error => qr{\A line [ ] 5: [ ] unsupported [ ] character}xms,
    },
    +{
        name     => 'a multi-line string before the error',
        cpanfile => "requires 'A', 'multi\nline';\nrequires \$b;\n",
        error    => qr{\A line [ ] 3: [ ] unsupported [ ] character}xms,
    },
    +{
        name     => 'a block without an opening brace',
        cpanfile => "on test => sub requires 'A';\n",
        error    => qr/\A line [ ] 1: [ ] expected [ ] '[{]'/xms,
    },
    +{
        name     => 'a parenthesised block without a closing parenthesis',
        cpanfile => "on('test', sub { requires 'A' };\n",
        error    => qr{\A line [ ] 1: [ ] expected [ ] '[)]'}xms,
    },
    +{
        name     => 'a parenthesised feature without a closing parenthesis',
        cpanfile => "feature('name', sub { requires 'A' };\n",
        error    => qr{\A line [ ] 1: [ ] expected [ ] '[)]'}xms,
    },
    +{
        name     => 'a mirror without a quoted url',
        cpanfile => "mirror cpan;\n",
        error    => qr{\A line [ ] 1: [ ] expected [ ] a [ ] quoted}xms,
    },
    +{
        name     => 'a parenthesised mirror without a closing parenthesis',
        cpanfile => "mirror('https://cpan.example.org';\n",
        error    => qr{\A line [ ] 1: [ ] expected [ ] '[)]'}xms,
    },
    +{
        name     => 'an invalid version string',
        cpanfile => "requires 'A', 'abc';\n",
        error    => qr{abc}xms,
    },
);

subtest 'with a valid cpanfile' => sub {
    my $dir      = tempdir(CLEANUP => 1);
    my $cpanfile = path($dir) -> child('cpanfile');
    $cpanfile -> spew(
        "requires 'Plack';\nrequires 'Mojolicious', '==9.31';\n");

    my $result = parse_cpanfile($dir);

    is($result -> {success}, 1, 'Parsing is marked as successful');
    is_deeply(
        $result -> {data},
        [
            {module => 'Mojolicious', version => '9.31', has_version => 1},
            {module => 'Plack',       version => undef,  has_version => 0},
        ],
        'Correctly parses modules with and without versions'
    );
};

subtest 'with a non-existent cpanfile' => sub {
    my $dir    = tempdir(CLEANUP => 1);
    my $result = parse_cpanfile($dir);
    is($result -> {success}, 0, 'Parsing is marked as unsuccessful');
    is($result -> {reason},
        'cpanfile_not_found', 'Reason is cpanfile_not_found');
    is_deeply($result -> {data},
        [], 'Data is an empty list for missing cpanfile');
};

subtest 'with an empty cpanfile' => sub {
    my $dir = tempdir(CLEANUP => 1);
    path($dir) -> child('cpanfile') -> touch;
    my $result = parse_cpanfile($dir);
    is($result -> {success},
        1, 'Parsing is marked as successful for empty file');
    is_deeply($result -> {data},
        [], 'Returns an empty list for empty cpanfile');
};

subtest 'with only comments and whitespace' => sub {
    my $result = parse_cpanfile(build_project("# nothing\n\n   \t\n"));

    is($result        -> {success}, 1, 'Parsing is marked as successful');
    is_deeply($result -> {data}, [], 'Returns an empty list');
};

subtest 'with phases, shortcuts, options and features' => sub {
    my $dir = build_project(<<'CPANFILE');
# dependencies
requires 'perl', '5.010';
requires "Range::Module" => '>= 1.0, < 2.0';
requires('Paren::Module', '1.5');
recommends 'Recommended::Module', 2;
suggests 'Suggested::Module';
requires 'Numeric::Module', 1.10;
requires 'Options::Module', '1.2', dist => 'X/Options-1.2.tar.gz';
requires 'Escaped::Module', '1', note => 'it\'s fine';
mirror 'https://cpan.example.org';
test_requires 'Test::Shortcut::Module', '0.9';
build_requires 'Build::Shortcut::Module';
configure_requires 'Configure::Module', '1';
author_requires 'Author::Module', '3';
on test => sub {
    requires 'Range::Module', '1.5';
    recommends 'Test::Recommended::Module';
};
on('build', sub { requires 'Build::Module' });
on 'develop' => sub { requires 'Develop::Module', '1' };
feature 'sqlite', 'SQLite support' => sub {
    requires 'Feature::Module';
};
feature pg => sub { requires 'Short::Feature::Module' };
requires 'Last::Module'
__END__
anything here is ignored $$$
CPANFILE

    my $result = parse_cpanfile($dir);

    is($result -> {success}, 1, 'Parsing is marked as successful');
    is_deeply(
        $result -> {data},
        [
            dependency('Build::Module'),
            dependency('Build::Shortcut::Module'),
            dependency('Escaped::Module', '1'),
            dependency('Last::Module'),
            dependency('Numeric::Module',     '1.1'),
            dependency('Options::Module',     '1.2'),
            dependency('Paren::Module',       '1.5'),
            dependency('Range::Module',       '1.5, < 2.0'),
            dependency('Recommended::Module', '2'),
            dependency('Test::Recommended::Module'),
            dependency('Test::Shortcut::Module', '0.9'),
            dependency('perl',                   '5.010'),
        ],
        'Merges runtime, build and test requirements like Module::CPANfile'
    );
};

subtest 'reads the literal cpanfile syntax' => sub {
    foreach my $case (@ACCEPTED_CASES) {
        my $result = parse_cpanfile(build_project($case -> {cpanfile}));

        is($result -> {error},   undef, "Reads $case->{name} without error");
        is($result -> {success}, 1,     "Reads $case->{name}");
        is_deeply(
            $result -> {data},
            $case   -> {expected},
            "Extracts the dependencies from $case->{name}"
        );
    }
};

subtest 'rejects syntax it cannot read without running it' => sub {
    foreach my $case (@REJECTED_CASES) {
        my $directory = build_project($case -> {cpanfile});
        my $result    = parse_cpanfile($directory);

        is($result -> {success}, 0, "Rejects $case->{name}");
        is($result -> {reason},
            'cpanfile_invalid', "Marks $case->{name} as invalid");
        like(
            $result -> {error},
            $case   -> {error},
            "Explains what is wrong with $case->{name}"
        );
        unlike($result -> {error},
            qr{\n}xms, "Reports $case->{name} on a single line");
        is_deeply($result -> {data},
            [], "Returns no dependencies for $case->{name}");
        is(
            $result -> {cpanfile_path},
            path($directory) -> child('cpanfile') -> stringify,
            "Names the cpanfile for $case->{name}"
        );
    }
};

subtest 'never executes code in the cpanfile' => sub {
    my $marker_directory = tempdir(CLEANUP => 1);
    my $marker           = path($marker_directory) -> child('executed');
    my $script           = path($marker_directory) -> child('payload.pl');
    $script -> spew("open my \$handle, '>', '$marker';\n1;\n");

    my @payloads = (
        "open my \$handle, '>', '$marker'; requires 'JSON::PP';",
        "BEGIN { open my \$handle, '>', '$marker' } requires 'JSON::PP';",
        "requires 'JSON::PP', \"\@{[ system 'touch $marker' ]}\";",
        "requires 'JSON::PP', \"\${\\ system 'touch $marker'}\";",
        "requires 'JSON::PP', `touch $marker`;",
        "requires 'JSON::PP', qx{touch $marker};",
        "requires 'JSON::PP' if system 'touch $marker';",
        "requires do { system 'touch $marker'; 'JSON::PP' };",
        "requires sprintf('%s', system 'touch $marker');",
        "on test => sub { system 'touch $marker' };",
        "on test => sub { requires 'JSON::PP'; system 'touch $marker' };",
        "feature 'x' => sub { system 'touch $marker' };",
        q{use POSIX; requires 'JSON::PP';},
        "requires 'JSON::PP', 1 + system('touch $marker');",
        "requires 'JSON::PP', '1' . system('touch $marker');",
        "requires 'JSON::PP', '1', url => system('touch $marker');",
        "do '$script';",
        "require '$script';",
        "eval q{system 'touch $marker'}; requires 'JSON::PP';",
        "system 'touch $marker';",
        "exec 'touch', '$marker';",
        "sub requires { system 'touch $marker' } requires 'JSON::PP';",
        "*requires = sub { system 'touch $marker' };",
        "package Evil; system 'touch $marker';",
    );

    foreach my $payload (@payloads) {
        my $result = parse_cpanfile(build_project("$payload\n"));

        is($result -> {success}, 0, "Rejects: $payload");
        is($result -> {reason},
            'cpanfile_invalid', 'Reason is cpanfile_invalid');
        like($result -> {error}, qr{\A line [ ] 1: }xms, 'Reports the line');
        is_deeply($result -> {data}, [], 'Returns no dependencies');
    }

    ok(!-e $marker, 'No payload was executed');
};

subtest 'returns results that satisfy ParserResult' => sub {
    my @results = (
        parse_cpanfile(build_project("requires 'A', '1.0';\n")),
        parse_cpanfile(build_project("requires \$a;\n")),
        parse_cpanfile(tempdir(CLEANUP => 1)),
    );

    foreach my $result (@results) {
        ok(
            ParserResult -> check($result),
            'The result matches the declared type'
        );
    }
};

done_testing();
