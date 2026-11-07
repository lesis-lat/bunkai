package Bunkai::Component::Parser;

use 5.034;
use strict;
use warnings;

use Const::Fast;
use CPAN::Meta::Prereqs;
use English    qw(-no_match_vars);
use Exporter   qw(import);
use Path::Tiny qw(path);
use Try::Tiny;
use Type::Params    qw(signature);
use Types::Standard qw(Str);

use Bunkai::Types qw(ParserResult);

our @EXPORT_OK = qw(parse_cpanfile);

our $VERSION = '0.0.4';

const my %PREREQ_TYPE_BY_KEYWORD => (
    requires   => 'requires',
    recommends => 'recommends',
    suggests   => 'suggests',
    conflicts  => 'conflicts',
);

const my %PHASE_BY_SHORTCUT_KEYWORD => (
    configure_requires => 'configure',
    build_requires     => 'build',
    test_requires      => 'test',
    author_requires    => 'develop',
);

const my $DEFAULT_PHASE => 'runtime';

my $parse_cpanfile_check = signature(positional => [Str]);

sub new_token {
    my ($type, $value, $line) = @_;

    return +{type => $type, value => $value, line => $line};
}

sub count_newlines {
    my ($text) = @_;

    return $text =~ tr/\n//;
}

sub tokenize_cpanfile {
    my ($source) = @_;

    my @tokens;
    my $line = 1;
    pos($source) = 0;

    while (pos($source) < length $source) {
        if ($source =~ m{\G ([[:space:]]+)}gcxms) {
            $line += count_newlines($1);
            next;
        }

        if ($source =~ m{\G [#] [^\n]*}gcxms) {
            next;
        }

        if ($source =~ m{\G __(?:END|DATA)__ \b}gcxms) {
            last;
        }

        if ($source =~ m{\G ' ((?:[^'\\]|\\.)*) '}gcxms) {
            my $raw_text = $1;
            my $text     = $raw_text =~ s{\\([\\'])}{$1}gxmsr;
            push @tokens, new_token('literal', $text, $line);
            $line += count_newlines($raw_text);
            next;
        }

        if ($source =~ m{\G " ([^"\\\$\@]*) "}gcxms) {
            my $text = $1;
            push @tokens, new_token('literal', $text, $line);
            $line += count_newlines($text);
            next;
        }

        if ($source =~ m{\G (v[[:digit:]]+(?:[.][[:digit:]]+)*) \b}gcxms) {
            push @tokens, new_token('literal', $1, $line);
            next;
        }

        if ($source =~
            m{\G ([[:digit:]][[:digit:]_]*(?:[.][[:digit:]_]*)?)}gcxms)
        {
            my $digits = $1 =~ s{_}{}gxmsr;
            push @tokens, new_token('literal', q{} . (0 + $digits), $line);
            next;
        }

        if ($source =~ m{\G ([[:alpha:]_][[:word:]]*)}gcxms) {
            push @tokens, new_token('word', $1, $line);
            next;
        }

        if ($source =~ m{\G (=>|[,;{}()])}gcxms) {
            push @tokens, new_token('symbol', $1, $line);
            next;
        }

        my $character = substr $source, pos($source), 1;
        die "line $line: unsupported character '$character'\n";
    }

    push @tokens, new_token('end', q{}, $line);
    return \@tokens;
}

sub peek_token {
    my ($state) = @_;

    return $state -> {tokens} -> [$state -> {index}];
}

sub next_token {
    my ($state) = @_;

    my $token = peek_token($state);
    if ($token -> {type} ne 'end') {
        $state -> {index}++;
    }

    return $token;
}

sub is_symbol {
    my ($token, @symbols) = @_;

    if ($token -> {type} ne 'symbol') {
        return 0;
    }

    foreach my $symbol (@symbols) {
        if ($token -> {value} eq $symbol) {
            return 1;
        }
    }

    return 0;
}

sub describe_token {
    my ($token) = @_;

    if ($token -> {type} eq 'end') {
        return 'end of file';
    }

    return "'$token->{value}'";
}

sub fail_at {
    my ($token, $message) = @_;

    my $found = describe_token($token);
    die "line $token->{line}: $message, found $found\n";
}

sub expect_symbol {
    my ($state, $symbol) = @_;

    my $token = next_token($state);
    if (!is_symbol($token, $symbol)) {
        fail_at($token, "expected '$symbol'");
    }

    return $token;
}

sub expect_literal {
    my ($state) = @_;

    my $token = next_token($state);
    if ($token -> {type} ne 'literal') {
        fail_at($token, 'expected a quoted string or number');
    }

    return $token -> {value};
}

sub expect_separator {
    my ($state) = @_;

    my $token = next_token($state);
    if (!is_symbol($token, q{,}, '=>')) {
        fail_at($token, q{expected ',' or '=>'});
    }

    return;
}

sub expect_argument_separator {
    my ($state, $has_parenthesis) = @_;

    my $token = next_token($state);
    if (is_symbol($token, q{,}, '=>')) {
        return;
    }

    my $closing_symbol = q{';'};
    if ($has_parenthesis) {
        $closing_symbol = q{')'};
    }

    return fail_at($token, "expected ',' or $closing_symbol");
}

sub accept_open_parenthesis {
    my ($state) = @_;

    if (is_symbol(peek_token($state), '(')) {
        next_token($state);
        return 1;
    }

    return 0;
}

sub is_argument_list_end {
    my ($token, $has_parenthesis) = @_;

    if ($has_parenthesis) {
        return is_symbol($token, ')');
    }

    if ($token -> {type} eq 'end') {
        return 1;
    }

    return is_symbol($token, q{;}, '}');
}

sub parse_argument {
    my ($state) = @_;

    my $token = next_token($state);
    if ($token -> {type} eq 'literal') {
        return $token -> {value};
    }

    if ($token -> {type} eq 'word' && is_symbol(peek_token($state), '=>')) {
        return $token -> {value};
    }

    return fail_at($token, 'expected a quoted string or number');
}

sub parse_arguments {
    my ($state) = @_;

    my $has_parenthesis = accept_open_parenthesis($state);
    my @arguments       = (parse_argument($state));

    while (!is_argument_list_end(peek_token($state), $has_parenthesis)) {
        expect_argument_separator($state, $has_parenthesis);
        if (is_argument_list_end(peek_token($state), $has_parenthesis)) {
            last;
        }
        push @arguments, parse_argument($state);
    }

    if ($has_parenthesis) {
        expect_symbol($state, ')');
    }

    return @arguments;
}

sub add_prerequisite {
    my ($context, %prerequisite) = @_;

    my ($module, @requirement_arguments) = @{$prerequisite{arguments}};
    if (!length $module) {
        die "line $prerequisite{line}: module name must not be empty\n";
    }

    my $version = 0;
    if (@requirement_arguments % 2) {
        $version = $requirement_arguments[0];
    }

    if (defined $context -> {feature}) {
        return;
    }

    my $phase = $prerequisite{phase};
    my $type  = $prerequisite{type};
    $context -> {specs} -> {$phase} -> {$type} -> {$module} = $version;
    return;
}

sub parse_sub_block {
    my ($state, $context) = @_;

    my $token = next_token($state);
    if (!($token -> {type} eq 'word' && $token -> {value} eq 'sub')) {
        fail_at($token, q{expected 'sub'});
    }

    expect_symbol($state, '{');
    parse_statements($state, $context, '}');
    expect_symbol($state, '}');

    return;
}

sub parse_phase_statement {
    my ($state, $context) = @_;

    my $has_parenthesis = accept_open_parenthesis($state);
    my $phase           = parse_argument($state);
    expect_separator($state);
    parse_sub_block($state, +{%{$context}, phase => $phase});

    if ($has_parenthesis) {
        expect_symbol($state, ')');
    }

    return;
}

sub parse_feature_statement {
    my ($state, $context) = @_;

    my $has_parenthesis = accept_open_parenthesis($state);
    my $identifier      = parse_argument($state);
    expect_separator($state);

    if (peek_token($state) -> {type} eq 'literal') {
        next_token($state);
        expect_separator($state);
    }

    parse_sub_block($state, +{%{$context}, feature => $identifier});

    if ($has_parenthesis) {
        expect_symbol($state, ')');
    }

    return;
}

sub parse_mirror_statement {
    my ($state) = @_;

    my $has_parenthesis = accept_open_parenthesis($state);
    expect_literal($state);

    if ($has_parenthesis) {
        expect_symbol($state, ')');
    }

    return;
}

sub parse_statement {
    my ($state, $context) = @_;

    my $token = next_token($state);
    if ($token -> {type} ne 'word') {
        fail_at($token, 'expected a cpanfile keyword');
    }

    my $keyword = $token -> {value};

    if (exists $PREREQ_TYPE_BY_KEYWORD{$keyword}) {
        add_prerequisite(
            $context,
            phase     => $context -> {phase},
            type      => $PREREQ_TYPE_BY_KEYWORD{$keyword},
            line      => $token -> {line},
            arguments => [parse_arguments($state)],
        );
        return;
    }

    if (exists $PHASE_BY_SHORTCUT_KEYWORD{$keyword}) {
        add_prerequisite(
            $context,
            phase     => $PHASE_BY_SHORTCUT_KEYWORD{$keyword},
            type      => 'requires',
            line      => $token -> {line},
            arguments => [parse_arguments($state)],
        );
        return;
    }

    if ($keyword eq 'on') {
        parse_phase_statement($state, $context);
        return;
    }

    if ($keyword eq 'feature') {
        parse_feature_statement($state, $context);
        return;
    }

    if ($keyword eq 'mirror') {
        parse_mirror_statement($state);
        return;
    }

    die "line $token->{line}: unsupported statement '$keyword'\n";
}

sub is_block_end {
    my ($token, $terminator) = @_;

    if ($terminator eq 'end') {
        return $token -> {type} eq 'end';
    }

    return is_symbol($token, $terminator);
}

sub parse_statements {
    my ($state, $context, $terminator) = @_;

    while (!is_block_end(peek_token($state), $terminator)) {
        if (is_symbol(peek_token($state), q{;})) {
            next_token($state);
            next;
        }

        parse_statement($state, $context);

        my $token = peek_token($state);
        if (is_block_end($token, $terminator)) {
            last;
        }

        if (!is_symbol($token, q{;})) {
            fail_at($token, q{expected ';'});
        }
    }

    return;
}

sub read_cpanfile_prerequisites {
    my ($source) = @_;

    my $state   = +{tokens => tokenize_cpanfile($source), index => 0};
    my $context = +{phase  => $DEFAULT_PHASE, feature => undef, specs => {}};

    parse_statements($state, $context, 'end');

    my $prereqs = CPAN::Meta::Prereqs -> new($context -> {specs});
    return $prereqs -> merged_requirements -> as_string_hash;
}

sub build_dependencies {
    my ($module_hash) = @_;

    my @dependencies;
    foreach my $module (sort keys %{$module_hash}) {
        my $version = $module_hash -> {$module};

        $version =~ s{
            \A \s*
            (?:==|>=|<=|[<>])
            \s*
        }{}xms;

        my $module_version;
        my $has_version = 0;
        if ($version ne '0') {
            $module_version = $version;
            $has_version    = 1;
        }

        push @dependencies,
          +{
            module      => $module,
            version     => $module_version,
            has_version => $has_version,
          };
    }

    return \@dependencies;
}

sub parse_cpanfile {
    my ($project_path) = @_;

    ($project_path) = $parse_cpanfile_check ->($project_path);
    my $cpanfile_path = path($project_path) -> child('cpanfile');

    if (!-f $cpanfile_path) {
        return +{
            success       => 0,
            reason        => 'cpanfile_not_found',
            data          => [],
            cpanfile_path => $cpanfile_path -> stringify
        };
    }

    my $module_hash;
    my $error;
    try {
        $module_hash =
          read_cpanfile_prerequisites($cpanfile_path -> slurp_raw);
    }
    catch {
        my $exception = $ARG;
        $error = $exception =~ s{\s+\z}{}xmsr;
    };

    if (defined $error) {
        return +{
            success       => 0,
            reason        => 'cpanfile_invalid',
            error         => $error,
            data          => [],
            cpanfile_path => $cpanfile_path -> stringify
        };
    }

    return +{
        success       => 1,
        data          => build_dependencies($module_hash),
        cpanfile_path => $cpanfile_path -> stringify
    };
}

1;
