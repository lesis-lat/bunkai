<p align="center">
  <h3 align="center">Perl Style Guide</h3>
  <p align="center">A starting point for Perl development teams to provide consistency through good practices</p>
</p>

---

#### Summary

This paper is summarized in some good practice guidelines for Perl coding using "post-modern" practices. This work is in progress and any suggestions/contributions are welcome.

This project is just one of several other coding style guides, there is no intention of setting a pattern from it. Please do not take this as absolute truth. The most important thing here is that you and your team feel comfortable with a certain guideline and make use of it.

This paper is a fork of the paper written by [Eric Lorenzana](https://github.com/chusqui/perl-style-guide), with only a few changes in the sense of organization of the material and some adjustments to current market practices. 

---

#### Code layout

- Do not write any comments in the code. Your code must be self-explanatory without comments. [See the comments section.](#comments)

- All code must be written in English, using clear, descriptive, and intuitive variable, function, and method names.

- Make use of the "strict" and "warnings" modules in all your codes, they provided you:
    1. strict: It forces you to code properly to make your program less error-prone. For example: It forces you to declare variables before you use them. You can declare variable using “my” keyword. “my” keyword restricts the scope of the variable to local. It makes the code more readable and less error prone. If you don’t declare variable using my keyword then the created variable would be global, which you should avoid, reducing the scope of the variable to the place where it is needed is a good programming practice.

    2. warnings: It helps you find typing mistakes, it warns you whenever it sees something wrong with your program. It would help you find mistakes in your program faster.


- Try to limit your code to 72-78 column lines...
  - But don't stress over it. Real world code often has very long sentences, and trying to force them to be below 78 columns leads to tight, but ugly code. In a nutshell: <= 72 is perfect, <= 78 is great, > 78 is not as bad as some folks might try to make you believe.
  
- Use four spaces per indentation level. The main advantage being that it provides a consistent and readable format, making it easier to maintain code quality. This level of indentation also helps in keeping lines within a reasonable length, promoting better readability.

- Do not use tabs. It makes code difficult to browse in some hosts (where 8 spaces per tab is the standard) and only works when indenting by blocks.

---

#### Comments

Comments are not tolerated. A comment is a confession that the code failed to explain itself, and the fix is always the code, never the comment. Code is verified by the interpreter and by your tests; comments are verified by nobody. They rot silently, drift away from what the code actually does, and eventually lie to the next person reading them.

- Do not write comments. Rewrite the code until the comment is unnecessary.

- Never restate what the code already says.

```perl
# Bad
# increment the counter
$counter = $counter + 1;

# Good
$counter = $counter + 1;
```

- When you feel the urge to explain a value, name the value.

```perl
# Bad
# 86400 is the number of seconds in a day
if ($elapsed > 86400) {
  ...
}

# Good
my $seconds_in_a_day = 86400;

if ($elapsed > $seconds_in_a_day) {
  ...
}
```

- When you feel the urge to explain a block, extract it into a subroutine whose name is the explanation.

```perl
# Bad
# check whether the user is allowed to read the report
if ($user -> role eq "admin" || $user -> id == $report -> owner_id) {
  ...
}

# Good
if (user_can_read_report($user, $report)) {
  ...
}
```

- Never leave commented-out code behind. Delete it. Version control already remembers it, and dead code that looks alive is worse than no code at all.

```perl
# Bad
# my $result = old_implementation($input);
my $result = new_implementation($input);

# Good
my $result = new_implementation($input);
```

- Do not write banners, separators, author tags, dates, or changelogs in the source. All of this belongs to your version control system, where it stays accurate.

```perl
# Bad
##########################################
# Author: someone
# Created: 2024-01-01
# Changelog: fixed the parser
##########################################
```

- Do not write `TODO`, `FIXME`, or `HACK` notes. Pending work belongs in your issue tracker, where it can be assigned, prioritized, and closed. A note buried in the source is work nobody agreed to do.

- Do not explain a subroutine with a comment. If the name does not tell the whole story, the name is wrong or the subroutine does too much.

```perl
# Bad
# returns the user name and, if missing, the email
sub get_user {
  ...
}

# Good
sub user_name_or_email {
  ...
}
```

- If a piece of code needs justification, such as a workaround for an upstream bug or a deliberate deviation, that justification is history, not code. Write it in the commit message and in the issue that tracks it.

- Note that shebang lines and compiler directives are not comments, even though they start with `#`. They are instructions, they are read by the machine, and they stay.

```perl
#!/usr/bin/env perl
## no critic (ProhibitStringyEval)
```

- Note as well that POD is documentation, not commentary. A distributable module describes its public interface in POD, aimed at whoever consumes the module without reading the source. That is a contract for outsiders, and it never becomes an excuse to narrate the implementation from inside.

---
  
#### Good practices  

```perl
# Don't do this:
my $string =
  "Lorem ipsum dolor sit amet, consectetur adipisicing elit, sed do eiusmod tempor aliqua.";

# Do this instead:
my $string = "Lorem ipsum dolor sit amet, consectetur adipisicing elit, sed do eiusmod tempor aliqua."

my $fn = sub {$_[0] + 1};              # Bad
my $fn = sub { $_[0] + 1 };            # Good
```

* Don't cuddle an else.

```perl
# Good
if (condition) {
  ...
}

else {
  ...
}

# Bad
if (condition) {
  ...
} else {
  ...
}
```

```perl
# Good
sub function {
  if (test) {
    ...
  }
}

# Bad
sub function
{
  if (test)
  {
    ...
  }
}
```

- Always unpack the stack first.
- Do not, ever, modify the stack. Unless necessary.

```perl
# Bad
sub my_method {
  my $self = shift;
  my %params = @_;
  ...
}

# Good
sub my_method {
  my ($self, %params) = @_;
  ...
}
```

- Do not put spaces between spaces, braces and brackets. That is, arrays, hashes, array and hash references, string and command line delimiters.

```perl
my ( $self, $who, @params ) = @_;      # Bad
my ($self, $who, @params) = @_;        # Good

my $self = { name => "Eric", age => 26 };  # Bad
my $self = {name => "Eric", age => 26};    # Good

my @files = qx| ls $str |;             # Bad
my @files = qx|ls $str|;               # Good
```

- Please keep in mind that this does not apply to operators.

```perl
my $fn = sub {$_[0] + 1};              # Bad
my $fn = sub { $_[0] + 1 };            # Good

my @items = map {do_something_to $_} @_;    # Bad
my @items = map { do_something_to $_ } @_;  # Good
```

- Use whitespace between operators.

```perl
# Good
my $area = $pi * ($radius ^ 2);

# Bad
my $area = $pi*($radius^2);
```

- Always keep a space before and after the `->` operator.

```perl
my $name = $user->name;               # Bad
my $name = $user ->name;              # Bad
my $name = $user-> name;              # Bad
my $name = $user -> name;             # Good
```

- The one exception is inside an interpolated string, where the spaces stop Perl from dereferencing and you get the reference itself printed back. Write the arrow tight there, or pull the value out into a variable before the string, which is usually the better answer.

```perl
my $limits = {high => 5};

print "More than $limits -> {high} alerts\n";   # Bad, prints HASH(0x...)
print "More than $limits->{high} alerts\n";     # Good

my $high_limit = $limits -> {high};
print "More than $high_limit alerts\n";         # Better
```

- Do not use ternary operators; use explicit control flow blocks instead.

```perl
# Bad
my $status = $ok ? "ready" : "not ready";

# Good
my $status;
if ($ok) {
  $status = "ready";
}
if (!$ok) {
  $status = "not ready";
}
```

- Avoid using `else`; prefer early returns or separate conditional blocks.

```perl
# Bad
if ($valid) {
  return 1;
} else {
  return 0;
}

# Good
if ($valid) {
  return 1;
}
return 0;
```

- Do not use post-if conditions (e.g., `statement if condition`); always use explicit conditional blocks.

```perl
# Bad
log_event($event) if $event;

# Good
if ($event) {
  log_event($event);
}
```

- Associate hash key and values by using fat comma.

```perl

# Correct, but bad style
my %hash = (key1, 'val1',
            key2, 'val2',
            key3, 'val3');

# Good
my %hash = (
              key1 => 'val1',
              key2 => 'val2',
              key3 => 'val3'
           );
```

---

#### Recommended modules

- Use `Readonly` for constants and immutable values.

```perl
use Readonly;
Readonly my $PI => 3.1415926;
```

- Use `English` to refer to Perl's built-in variables by name instead of by punctuation. Punctuation variables force the reader to keep a lookup table in their head, and this guide expects code to explain itself.

```perl
use English qw(-no_match_vars);
```

```perl
# Bad
print $0;
print $!;
print $^O;
print $@;

# Good
print $PROGRAM_NAME;
print $ERRNO;
print $OSNAME;
print $EVAL_ERROR;
```

- Always import it with `-no_match_vars`. Importing the match variables (`$MATCH`, `$PREMATCH`, `$POSTMATCH`) used to slow down every regular expression in the program, and while modern Perl no longer pays that cost, the explicit import states that you do not want them and keeps the intent unambiguous.

---

#### Dependencies

- Declare every dependency in a `cpanfile` at the root of the project. A dependency that lives only in someone's shell history, in a README instruction, or in the memory of whoever set up the server is not a declared dependency.

- Pin exact versions with `==`. A floating version means the code you ship is not the code you tested, and the day it breaks will be a day when nothing in your repository changed.

```perl
# Bad
requires "Readonly";
requires "Try::Tiny", ">= 0.30";

# Good
requires "Readonly", "== 2.05";
requires "Try::Tiny", "== 0.31";
```

- Separate dependencies by phase, so that a production install does not drag in your test and profiling tools.

```perl
requires "Readonly", "== 2.05";
requires "Try::Tiny", "== 0.31";

on "test" => sub {
  requires "Test::More", "== 1.302195";
};

on "develop" => sub {
  requires "Devel::NYTProf", "== 6.14";
};
```

- Commit both `cpanfile` and `cpanfile.snapshot`. Pinning your direct dependencies does not pin theirs, and the snapshot produced by `carton install` locks the whole resolved tree. Without it, "pinned" only describes the first level.

- Install from the declaration, never by hand. `carton install` or `cpanm --installdeps .` guarantees that every machine builds the same tree from the same file. Anything installed manually exists on exactly one machine and disappears with it.

- Do not declare the modules that ship with perl. `File::Spec`, `File::Copy`, `Time::HiRes`, `Carp`, `English` and their kind arrive with the interpreter, and the version you have is usually the one bundled with your perl rather than one released to CPAN. Pinning that version produces a `cpanfile` nobody can install:

```
# Bad: the installed version exists only inside perl
requires "File::Spec", "== 3.94";
requires "Time::HiRes", "== 1.9778";
```

```
! Finding File::Spec (== 3.94) on cpanmetadb failed.
Found Time::HiRes 1.9764 which doesn't satisfy == 1.9778.
```

- What you declare instead is the perl you need, once:

```perl
requires "perl", "5.034";
```

- The trap is quiet, because everything keeps working on the machine where you wrote the pin. It surfaces in the first clean environment: a container build, or continuous integration. Before pinning a version you read from a running program, check that the version is on CPAN and not only in your interpreter.

- A module being core does not settle it either way. Several core modules are also released to CPAN on their own, and those are pinnable at the released versions. The question is never whether the module is core; it is whether that exact version can be fetched.

---

#### Performance tips

##### Profiling

- Profile your code with `Devel::NYTProf`.

---

#### Containers

A project that ships a container publishes it the same way everywhere, from a
single `container.yml`. One workflow covers both halves of the job, because
they share a build:

- On a pull request, the image is built and run. Building is not proof that the
  image works: a container whose entry point is broken builds perfectly. The
  workflow runs it and checks that it prints what it should.

- On a push to `main`, the same image is published to the GitHub Container
  Registry, tagged `latest` and with the short commit hash. The hash tag is what
  lets you say which commit an incident came from.

```yaml
env:
  IMAGE_NAME: ghcr.io/${{ github.repository }}
  SMOKE_ARGUMENTS: --help
  SMOKE_PATTERN: Tool v
```

- Those three variables are the only part that differs between projects.
  Everything below them is identical, so a fix to the pipeline is a fix
  everywhere.

- Assert the output, not the exit status. A tool that gates a pipeline exits
  non-zero on purpose, so `docker run` failing tells you nothing. What tells you
  the image is sound is that the right program answered.

- Build once. The verification step builds with `load: true` and no push; the
  publish step reuses the layer cache, so the image is not compiled twice.

- Publish to `ghcr.io`. `docker.pkg.github.com` is the retired registry and
  pushing there succeeds against nothing.

- Keep the image name in step with what consumers pull. An `action.yml` or a
  README that names a different path than the workflow publishes is a broken
  action that nobody notices until someone tries to use it.

---

#### Tests

- Split the suite by what each test proves, and keep the three kinds in their own directories under `tests/`.

```
tests/
  unit/          one module, in isolation
  integration/   several real modules together, in process
  e2e/           the program itself, run the way a user runs it
  mutation/      the mutation runner and the gate that reads its score
  lib/           helpers the tests share, never the code under test
```

- A **unit** test exercises one module and mocks whatever it talks to. It proves a single piece behaves.

- An **integration** test wires real modules together in the same process, and is allowed to touch the disk or drive a mocked transport. It proves the pieces agree with each other. A component that mocks its own subprocess still belongs here: nothing real is being launched.

- An **end to end** test runs the program as a user would, as a separate process, and reads only what the program hands back: standard output, the exit status, and the files it wrote. It imports none of your modules to make its assertions. It proves the thing you actually ship works.

```perl
sub run_tool {
    my (@arguments) = @_;

    my $command = join q{ },
      map { quotemeta } ($EXECUTABLE_NAME, '-Ilib', 'tool.pl', @arguments);

    my $output = qx{$command 2>&1};

    return {
        output => $output,
        status => $CHILD_ERROR >> $EXIT_STATUS_SHIFT,
    };
}
```

- The exit status is part of your interface, so assert it. A tool that gates a pipeline has to fail when it finds something, and a tool that writes a report may have to succeed anyway so the report still gets collected. Those two rules contradict each other often enough that only an end to end test will hold them straight.

- Run each kind on its own, so a failure names the layer that broke.

```
prove -Ilib -Itests/lib -r tests/unit
prove -Ilib -Itests/lib -r tests/integration
prove -Ilib -Itests/lib -r tests/e2e
```

- Locate the libraries with `FindBin` rather than a path relative to the working directory. A test that only passes when `prove` is run from one particular directory is a test that will fail in continuous integration.

```perl
# Bad
use lib '../lib';

# Good
use FindBin;
use lib "$FindBin::Bin/../../lib";
use lib "$FindBin::Bin/../lib";
```

- Put anything the tests share in `tests/lib`, under a `Test` namespace of your own distribution. `<Namespace>::Test::Directory` creates a private temporary directory and removes it when the process ends, so no test has to clean up after itself.

---

#### Mutation testing

Coverage tells you which lines ran. It does not tell you whether anything would have noticed had those lines been wrong. Mutation testing answers that: it changes the source in small, plausible ways and reruns the suite. A mutant that survives is a change to your code that no test objects to.

- Use `Devel::Mutator`, and drive it from `tests/mutation/run.pl`. The runner copies the project into a private directory, generates the mutants there, runs the suite against each one, and prints the score with every survivor named and diffed. Nothing is ever mutated in your working tree.

- Mutate the code you ship, which is your library **and** the program that drives it. A runner pointed only at `lib` reports a perfect score for a project whose logic lives in its entry script, and a gate that can only pass is not a gate.

- Run the mutants against `tests/unit` and `tests/integration` only. Every mutant reruns the whole suite, and end to end tests spawn a process per case, so including them multiplies the wall clock for findings the faster layers already catch.

```
perl tests/mutation/run.pl --limit 40
```

- `tests/mutation/Mutation.t` is the same run wired into the suite. It skips unless you ask for it, so the ordinary suite stays fast.

```
<PROJECT>_MUTATION=1 prove -Ilib -Itests/lib tests/mutation/Mutation.t
```

- Set the floor from the score you actually measure, not from an aspiration. A floor above the current score fails every build from the first day and teaches the team to ignore the job. Raise it deliberately, once the survivors that matter are dead.

```
perl tests/mutation/run.pl --limit 80 --minimum 85
```

- Read the survivors before trusting the score. Some mutants are equivalent: `$text =~ s/a/b/` and `$text !~ s/a/b/` both perform the substitution, and `//` and `||` agree unless the value is false but defined. Those can never be killed and quietly cap your score. The survivors worth acting on are the ones that describe a real behaviour nothing asserts.

---

#### Enforcement

This repository ships the configuration that turns the rules above into a gate. Copy `.perltidyrc`, `.perlcriticrc` and `.editorconfig` to the root of every project, and keep them identical across repositories. A rule that is only written down is a rule that drifts.

- `.perltidyrc` encodes every layout rule in this guide: four-column indentation, a 78 column limit, tight parentheses, brackets and data braces, spaced block braces, spaces around `->`, no cuddled else, and no tabs. Run it before every commit.

```
perltidy -b -bext='/' $(find . -name '*.pl' -o -name '*.pm' -o -name '*.t')
```

- `.perlcriticrc` runs `Perl::Critic` at severity 1 and enables `CodeLayout::RequireTidyCode`, which reads the `.perltidyrc` above. This is what catches formatting that was never tidied.

```
perlcritic --profile .perlcriticrc .
```

- `bin/lesis-style-check.pl` covers the rules that neither `perltidy` nor `Perl::Critic` can express: comments, ternary operators, `else` blocks, statement modifiers, `shift` based stack unpacking, punctuation variables, a spaced `->` inside an interpolated string, `use constant` in place of `Readonly`, `use English` without `-no_match_vars`, unpinned dependencies, and a missing `cpanfile.snapshot`. It needs `PPI` and `Readonly`.

```
perl bin/lesis-style-check.pl .
```

- Wire all three into continuous integration. A gate that runs on a developer's machine only is a gate that runs when the developer remembers it.

---

#### Contribution

- Your contributions and suggestions are heartily ♥ welcome. [See here the contribution guidelines.](https://github.com/lesis-lat/perl-style-guide/blob/master/.github/CONTRIBUTING.md) Please, report bugs via [issues page.](https://github.com/lesis-lat/perl-style-guide/issues)  and for security issues see here the [security policy.](https://github.com/lesis-lat/perl-style-guide/blob/master/SECURITY.md) (✿ ◕‿◕) 

---

#### License

- This work is licensed under [MIT License.](https://github.com/lesis-lat/perl-style-guide/blob/master/LICENSE.md)
