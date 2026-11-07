# Mutation testing

Line coverage says which code ran. Mutation testing says whether the tests would
have *noticed* if that code were wrong.

[`Devel::Mutator`](https://metacpan.org/pod/Devel::Mutator) rewrites one operator
at a time in the source under `lib/` (`==` to `!=`, `&&` to `||`, `>` to `<=`,
and so on) and runs the suite against each rewritten copy. A mutant that makes
the suite fail is *killed*: some test asserted the behaviour that changed. A
mutant that leaves the suite green *survived*: that operator is executed by the
tests but its result is never asserted.

## Running

```bash
perl tests/mutation/run-mutation-tests.pl
```

Restrict the run to specific files or directories:

```bash
perl tests/mutation/run-mutation-tests.pl lib/Bunkai/Component/Updater.pm
```

Options:

| Option | Default | Meaning |
| --- | --- | --- |
| `--timeout N` | `60` | Seconds allowed per mutant before it is reported as `n/a`. |
| `--command CMD` | `cd tests && prove *.t` | Command whose exit status decides whether a mutant was killed. |
| `--keep` | off | Print the workspace path instead of letting it be discarded. |

Exit status is `0` when every mutant was killed and `1` when any survived.

## Why the runner exists

`mutator test` works by overwriting the real source file with each mutant,
running the command, then moving the original back. Interrupt it and the working
tree is left holding mutated source and `.bak` files.

`run-mutation-tests.pl` copies `lib/`, `tests/` and `cpanfile` into a temporary
directory and does all of that there, so the working tree is never modified. The
temporary directory is removed when the run ends.

## Scope

The default targets are `lib/Bunkai/Component`, `lib/Bunkai/Network` and
`lib/Bunkai/Utils`. Pass paths explicitly to run against anything else.

## Reading a survivor

Survivors are reported as `not ok`, followed by a diff. The diff shows the
mutated line against the original, which is the assertion that is missing.

## Known surviving mutants

The current score is 112 killed out of 121. The nine survivors are equivalent or
unreachable mutants, not missing assertions, and no test can kill them:

**`=~ s///` rewritten to `!~ s///`** — four survivors, in `Auditor.pm`,
`Parser.pm` and `Updater.pm` (twice). `!~` still performs the substitution; it
only negates the boolean that the statement throws away. The two forms are
behaviourally identical.

**`//` rewritten to `||`** — five survivors. These differ only when the left
operand is *defined but false*, meaning the empty string or the string `0`:

| Location | Why it cannot be killed |
| --- | --- |
| `Fetcher.pm`, `$module -> distribution // q{}` | Neither `0` nor `q{}` equals `perl`, so the branch is taken either way. |
| `Updater.pm`, `$vulnerability -> {type} // q{}` | Neither `0` nor `q{}` equals `error`, so the branch is taken either way. |
| `Auditor.pm`, `$stdout // q{}` and `$stderr // q{}` | Requires `cpan-audit` to print exactly `0` on one stream and an advisory on the other. |
| `Updater.pm`, `$fixed_version // $latest_version` | Requires an advisory whose fixed range parses to version `0`. |

Killing the last two would mean asserting behaviour for inputs the tool cannot
produce. They are left alive deliberately.

Re-check this list when the score changes: a *new* survivor is a real gap until
shown otherwise.
