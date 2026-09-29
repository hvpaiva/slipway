# Architecture

A map of the code for maintainers. The user-facing behavior is in [README.md](README.md) and
the man pages; this file explains where things live and why they are shaped the way they are.

## Layers

Everything is under `lib/slipway`, loaded by `lib/slipway.rb`, with no runtime gem dependencies.

| Layer | Directory | What lives there |
| --- | --- | --- |
| Command layer | `cli/` | `Registry`, `Command`, `Option`, `Positional`, `Example` (the data model), `Globals` (the options every command accepts), `Parser` (OptionParser adapter), `Validator`, `Runner` (front controller), `HelpRenderer`, `Completer` and `CompletionScripts`, `Manpage`, `Builtins`, `Context`, `Style` and `Theme`, `UsageError`. It knows nothing about projects or git. |
| Domain | `error.rb`, `yaml.rb`, `resources.rb`, `manifest.rb`, `store.rb`, `names.rb`, `labels.rb`, `selector.rb`, `config.rb`, `paths.rb`, `editor.rb` | `Slipway::Error` (the base of every failure reported to the user), the one YAML writer, `Project` and `Group` values, their YAML form, the on-disk store, name and label rules, the label selector grammar, XDG paths, the config file and the editor launcher. |
| Git adapter | `git/`, `state.rb` | `Git::Runner` is the one place that spawns git; `Git::Repository` asks the three questions slipway needs (status, last commit, remote); `Git::Status` and `Git::Commit` parse the answers; `Git::Fake` stands in for tests. `State` reduces a status or an error to the one STATUS word. |
| Output | `output/` | `Table`, `Describe`, `Serializer` (json and yaml) and `Age`. They render plain data through a `Context` and never touch resources. |
| Views | `views/` | `Views::Project` and `Views::Group` turn a resource, or an `Inspection`, into table rows, describe entries and the object hash json and yaml print. No I/O. |
| Commands and runtime | `commands/`, `runtime.rb`, `inspector.rb` | One class per verb. `Runtime` bundles config, paths, store, git, inspector and clock for one run; `Inspector` reads many repositories on a thread pool and preserves order. |

Dependencies point one way: commands use the runtime, views and output; views use the domain,
the git values and output; output paints through the command layer's `Context`; the command
layer and the domain depend on nothing else in the gem.

## One invocation

`exe/slipway` calls `Slipway.run(ARGV)`. From there:

1. `Commands.registry(factory)` builds the `CLI::Registry`: the eight verbs from
   `Commands::VERBS`, each built by its class's `self.command(factory)`, plus the builtins
   (`help`, `version`, `completion`, `man`, hidden `__complete`).
2. `Runtime.color_defaults` peeks at `--config` in argv and reads the config file once, so the
   `color` and `theme` keys can act as fallbacks before any option is parsed.
3. `CLI::Runner#run` walks the command tree. Global options may appear before the verb, between
   a group and its subcommand, and after the verb (`Parser#order!` while walking, `#permute!` on
   the leaf). Color is re-resolved after every parse step so `--color` applies to the error that
   may follow it. `--help`, `--version` and a bare group name return early.
4. `Validator` checks arity, positional enums, required options and option enums, raising
   `UsageError` (exit 2) with a `See 'slipway get --help' for usage.` hint.
5. The command's handler is an instance of `Commands::Base`. `call` asks the factory for a
   `Runtime` (`Runtime.build` in production, a hand-built one in tests) and hands off to `run`.
6. `Commands::Scope` resolves the type word, the group in effect, `-A` and the selector, then
   reads from the `Store`. For projects, `Inspector#examine_all` runs `Git::Repository` per path
   (`#examine` for one) and `State.derive` names the state.
7. `Views` turn the results into rows or entries, `Output` renders them through the `Context`,
   whose two `Style` objects decide color for stdout and stderr separately.
8. `Runner#execute` maps failures to exit statuses: `Slipway::Error` prints `error: MESSAGE`
   and exits 1 (2 for `UsageError`), `Interrupt` exits 130, `Errno::EPIPE` exits 0 quietly, and
   any other `StandardError` exits 1, with class and backtrace added when `SLIPWAY_DEBUG` is set.

## One definition, four outputs

A `CLI::Command` is plain data: name, summary, description, section, examples, positionals,
options, subcommands, handler. The same object feeds

- parsing and validation (`Parser`, `Validator`),
- `slipway VERB --help` and `slipway help VERB` (`HelpRenderer`),
- `man/man1/slipway-VERB.1` (`Manpage`, run by `bin/generate-man`),
- shell completion (`Completer`, answering `slipway __complete WORDS...` with cobra's directive
  protocol; the bash, zsh and fish scripts only relay that answer).

Nothing about a verb is written twice. Help text, option descriptions and examples live in the
verb's class (`DESCRIPTION`, `self.examples`, shared options in `Commands::Options`), and the
man page environment section is built from `Config::SETTINGS` and a list in `Manpage`, which
`test/unit/seams_test.rb` compares against the variables the code reads.

## Adding things

**A verb.** Create `lib/slipway/commands/<verb>.rb` with a class under `Commands` inheriting
`Base`. Define `self.command(factory)` returning a `CLI::Command` (set `section:` to one of
`Basic Commands`, `Settings Commands`, `Other Commands`; pass `handler: new(factory)`) and
`run(runtime, context, args, opts)`. Reuse `Options::TYPE`, `Options.name_positional(factory)`,
`Options::DRY_RUN` and friends. Require the file in `commands.rb` and add the class to `VERBS`
in help order; `test/unit/commands/registry_test.rb` asserts that order. Print results through
`result_line` (`project/hldr created`) and raise `Slipway::Error` or `CLI::UsageError` rather
than writing to stderr. Run `rake generate` so the new man page lands in `man/man1`.

**An option.** Add a `CLI::Option` (`long:`, optional `short:`, `argument:` for a value,
`enum:` for a closed set, `default:`, `repeatable:`, `required:`, `optional:` plus `implicit:`
for `--flag[=VALUE]`) to the command's `options:`. Read it in `run` as `opts[:long_name]`
(`--no-headers` becomes `opts[:no_headers]`). Help, the man page and completion pick it up;
an `enum` is also its completion list.

**A completer.** Give an `Option` or `Positional` a `completer:` proc. It receives the
positional words typed so far and returns an Array of values, a Hash of value to description,
or `CLI::Completer::FILES` to hand the shell its file completion. `Options.name_positional`
shows the pattern for values that need the store: build the runtime through the factory, and
return `[]` on any error, because a completion must never fail in the shell.

**A theme role.** Add the role to `CLI::Theme::DARK` (and to the `LIGHT` merge when the light
value differs), as an SGR parameter string or an Array for roles cycled by index. Paint with
`context.paint(:role, text)` or `context.style.paint_cycle(:role, index, text)`. The theme test
holds a copy of both presets and `seams_test.rb` checks that every `State::ROLES` entry exists
in both themes.

## Testing

Tests are Minitest, run with Ruby warnings on. `rake test` runs everything under `test/`;
`test:unit` and `test:integration` run one directory each. Three kinds exist:

- Unit tests under `test/unit`, one directory per layer. `CliHelper#run_cli` runs
  `Slipway.run` in-process with a `StringIO` `Context` and a Hash environment and returns
  `[status, stdout, stderr]`; a `runtime:` argument replaces the production factory.
  `CommandsHelper` builds that `Runtime` over a `Sandbox` (a temporary HOME with XDG
  directories) with `Git::Fake`, a fixed clock and canned statuses, so ages and states are
  exact and no test touches the real registry or git.
- Integration tests under `test/integration`. `IntegrationHelper#slipway` runs `exe/slipway`
  in a subprocess (`Open3.capture3` with `unsetenv_others`) inside a throwaway HOME, seeds the
  registry through `apply -f -`, and reads kubectl tables back cell by cell. Repositories come
  from `GitFixtures#build_repo`, which builds real repositories in named states (`clean`,
  `staged`, `unstaged`, `untracked`, `ahead`, `behind`, `diverged`, `detached`, `unborn`,
  `conflicted`, `gone`, `stash`, `plain_dir`) with a pinned environment and dates, so the same
  recipe yields the same commit ids on every machine. The git adapter and the inspector are
  unit-tested against the same fixtures with the real `git`.
- Golden tests under `test/golden` compare the help page of every command, the three completion
  scripts and the man pages with the files under `test/fixtures/golden` and `man/man1`;
  `UPDATE_GOLDEN=1` rewrites the fixtures after an intended change. `ShellHarness` also drives
  the completion scripts inside real shells (bash always; zsh and fish when installed, or
  unconditionally when `SLIPWAY_REQUIRE_SHELLS` is set, which the CI `completions` job does)
  against a stub program that answers `__complete` from a `FixtureRegistry`.

## Generated artifacts

`man/man1/*.1` are the only generated files in the tree. `bin/generate-man` (`rake generate`)
renders them from the registry with the date of the newest `## [x.y.z] - YYYY-MM-DD` heading in
`CHANGELOG.md`, or `SOURCE_DATE_EPOCH` when there is none, so a rebuild is byte-identical.
`rake lint:man` runs groff over them; CI regenerates and diffs them. `slipway man` reads the
pages from the gem's own `man/man1`, so they must be committed and shipped, and
`.gitattributes` marks them `linguist-generated`. The completion scripts are rendered at run
time by `slipway completion`, and the `rake lint:shell` task runs ShellCheck over the bash one.
