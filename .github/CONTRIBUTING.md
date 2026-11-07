# Contributing to Bunkai

## Branches

The `main` branch holds released code only. Open any new feature or bugfix
against `develop`, where it is tested before it lands in `main`.

## Style

The code follows the [LESIS Perl style guide](https://github.com/lesis-lat/perl-style-guide).
Two gates enforce it, and both run in continuous integration:

```
perltidy -b -bext='/' $(find lib tests -name '*.pl' -o -name '*.pm' -o -name '*.t')
perlcritic --profile .perlcriticrc .
```

The rules that neither tool can express are checked by the style guide's own
script, which reports comments, ternaries, `else` blocks, statement modifiers
and unpinned dependencies.

## Testing

Every change arrives with the tests that would have caught its absence. The
suite is split by what each test proves, and a pull request runs all three:

| Directory | What it proves |
| --- | --- |
| `tests/unit` | one module behaves, in isolation |
| `tests/integration` | the real modules agree with each other |
| `tests/e2e` | the program works when run the way a user runs it |

```
prove -Ilib -Itests/lib -r tests/unit
prove -Ilib -Itests/lib -r tests/integration
prove -Ilib -Itests/lib -r tests/e2e
```

A bugfix that is not a typo, a comment or whitespace needs one more step: find
out why the existing tests did not catch the bug, and fix that too.

## Mutation testing

Coverage says which lines ran. It does not say whether a test would have
noticed had those lines been wrong. `tests/mutation/run.pl` answers that by
changing the source in small ways and rerunning the suite.

```
perl tests/mutation/run.pl --limit 40
```

A surviving mutant is a change to the code that no test objects to. Read the
survivors before trusting the score: some are equivalent and can never be
killed.

## Dependencies

Every dependency is declared in `cpanfile` and pinned with `==`, and
`cpanfile.snapshot` is committed alongside it. Add a dependency by editing the
`cpanfile` and running `carton install`, never by installing it by hand.

## Large rewrites

Open a discussion issue before you begin, so we can agree the direction is
worth the work.

## License

By opening a pull request in this repository, you agree to provide your work
under the [project license](../LICENSE.md).
