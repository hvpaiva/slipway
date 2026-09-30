# Architecture

A map of the code for maintainers. The user-facing behavior is in [README.md](README.md) and
the man pages; this file explains where things live and why they are shaped the way they are.

## Layers

Everything is under `lib/slipway`, loaded by `lib/slipway.rb`, with no runtime gem dependencies.

| Layer | Directory | What lives there |
| --- | --- | --- |
| Command layer | `cli/` | `Registry`, `Command`, `Option`, `Positional`, `Example` (the data model), `Globals` (the options every command accepts), `Parser` (OptionParser adapter), `Validator`, `Runner` (front controller), `HelpRenderer`, `Completer` and `CompletionScripts`, `Manpage`, `Builtins`, `Context`, `Style` and `Theme`, `UsageError`. It knows nothing about projects or git. |
| Domain | `error.rb`, `yaml.rb`, `resources.rb`, `manifest.rb`, `store.rb`, `names.rb`, `labels.rb`, `selector.rb`, `field_selector.rb`, `config.rb`, `paths.rb`, `editor.rb`, `scanner.rb` | `Slipway::Error` (the base of every failure reported to the user), the one YAML writer, `Project` and `Group` values, their YAML form, the on-disk store, name and label rules, the label and field selector grammars, XDG paths, the config file, the editor launcher and the search for repositories under a directory that `create project --from-dir` registers. |
| Git adapter | `git/`, `state.rb` | `Git::Runner` is the one place that spawns git; `Git::Repository` asks the questions slipway needs (status, last commit, remote, time of the last fetch, whether the branch tracks a local one, whether a fetch without a remote argument has one to use, the git directory its worktrees share, the operation in progress, how far HEAD is from a pinned revision and how many of its commits the upstream lacks, the moves the branch reflog records and how many commits lie between two of them) and fetches with its own timeout, a no-prompt environment and only the transports the `protocols` setting lists; its `FastForwarding` part fast-forwards the checked-out branch under the same profile, one of the two writes to a working tree, raising `Git::Blocked` when the repository is in no state to move or git refuses, and its `RollingBack` part moves the branch back with `git reset --keep`, the one reset slipway runs, only to a commit HEAD contains and only when the upstream holds every commit the move drops; `Git::Status`, `Git::Commit`, `Git::FetchResult` and `Git::Reflog` parse the answers, `Git::Distance` holds how far HEAD is from a commit, and `Git::FastForward` and `Git::MoveBack` report a move; `Git::Url` validates a remote URL and redacts the credentials in one; `Git::BranchName` validates a branch name; `Git::Fake` stands in for tests. `State` reduces a status or an error to the one STATUS word. |
| Reconciliation | `drift.rb`, `plan.rb`, `rollout.rb` | `Drift` holds the drift types (Missing, Remote, Branch, Revision, Behind) and the blockers with their fixed sentences. `Plan.for` reads one `Inspection` into the drift sync would resolve, the drift it leaves alone and the blockers that stop it; a `spec.revision` pin replaces the upstream as where the branch should be, reached only forward and only along the upstream. It runs no git and reads no file, so every verb that shows drift reads the same answer. `Rollout::History` numbers the revisions of a branch from the reflog entries whose subject starts with `slipway `, and the commits the branch stood at before those moves. |
| Output | `output/` | `Table`, `Describe`, `Serializer` (json and yaml) and `Age`. They render plain data through a `Context` and never touch resources. |
| Views | `views/` | `Views::Project` and `Views::Group` turn a resource, or an `Inspection`, into table rows, describe entries and the object hash json and yaml print, and list in `FIELDS` the paths of that hash a field selector may name. No I/O. |
| Commands and runtime | `commands/`, `runtime.rb`, `inspector.rb`, `fetcher.rb`, `sync.rb`, `rollback.rb`, `pool.rb` | One class per verb. `Runtime` bundles config, paths, store, git, inspector and clock for one run; `Inspector` reads many repositories on a `Pool`, asks how far HEAD is from `spec.revision` only of a pinned project whose HEAD is elsewhere, and asks for the operation in progress only of a project the plan would fast-forward; the `Pool` runs one block per item on a bounded number of threads and hands the results back in input order, all at once (`map`) or each as soon as every earlier one is done (`each_ordered`). `Fetcher` fetches one project and names the outcome (fetched, unchanged, skipped, paused, denied, failed); projects on one repository, such as a linked worktree and its main one, fetch one after the other, because they write the same refs. `Commands::Results` runs a verb's work on a `Pool` of its own, sized by the `parallel` setting, and prints each project's result through `each_ordered`, so the lines stream in the order listed, then the count of the results. `Sync::Executor` drives the fast-forward: its workers inspect, fetch through `Fetcher`, inspect again and plan with `Plan.for`, and the calling thread fast-forwards each project as its result comes up, so no two of its writes run at once and a move shares the fetches' lock on its repository. `Rollback` is the only caller of the move back and the other caller of the fast-forward: it checks the project as sync would, picks the revision from `Rollout::History`, moves the branch back with the reset or forward with the fast-forward, and writes `spec.revision` only after git moved it. A call that ends early, on an exception or an interrupt, kills and joins its workers first, so their `ensure` blocks stop any git they started. |

Dependencies point one way: commands use the runtime, views and output; views use the domain,
the git values, the plan and output; output paints through the command layer's `Context`. The
command layer and the domain (with the git adapter and reconciliation) sit at the bottom:
neither requires commands, views, the runtime, the inspector, the fetcher, sync, the rollback or
the pool. The command layer requires one domain file, the one allowed edge: `cli/errors.rb`
requires `error.rb`, because `CLI::UsageError` is a `Slipway::Error`. The domain may use the
command layer: `labels.rb`, `selector.rb` and `field_selector.rb` raise `CLI::UsageError`, and
`config.rb` validates against `CLI::Theme` and `CLI::Style`. `test/unit/conventions_test.rb`
reads every `require_relative` under `lib/` and fails on an edge that breaks these rules.

## One invocation

`exe/slipway` calls `Slipway.run(ARGV)`. From there:

1. `Commands.registry(factory)` builds the `CLI::Registry`: the eleven verbs from
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
   (`#examine` for one) and `State.derive` names the state. A field selector is matched after
   that, on the object hash json prints, because some of its fields are what git answered.
7. `Views` turn the results into rows or entries, `Output` renders them through the `Context`,
   whose two `Style` objects decide color for stdout and stderr separately.
8. `Runner#execute` maps failures to exit statuses: `Slipway::Error` prints `error: MESSAGE`
   and exits 1 (2 for `UsageError`), `Interrupt` exits 130, `Errno::EPIPE` exits 0 quietly, and
   any other `StandardError` exits 1, with class and backtrace added when `SLIPWAY_DEBUG` is set.

Every table cell, describe value and `result_line` name passes `Output.plain`, which makes
control and bidirectional characters visible, and so do the fields git answered in json and
yaml output. Warning lines are written only by `Output.warning`, which passes the message
through the same rule. The runner's error lines pass it through `CLI::Style.plain`; only a
`UsageError` takes `layout: true`, which keeps the line feeds and tabs of a "Did you mean
this?" list. A remote URL git reports passes `Git::Url.redact`, and a git failure keeps only
the first line of git's stderr, redacted and cut to 200 characters. `spec.remote` is refused,
from `--remote` or a manifest, whenever redact would change it, so json and yaml print it as
stored.

## Safety promises

[SECURITY.md](SECURITY.md#safety-promises) lists what slipway promises about the git it runs,
the writes to a working tree, the environment git gets and what reaches the terminal. A few
places keep those promises: `Git::Runner` spawns every git process and sets its environment;
`Git::Repository` holds every git argv, its `FastForwarding` part the fast-forward, which only
`Sync::Executor` and `Rollback` call, and its `RollingBack` part the reset, which only
`Rollback` calls; `Manifest`, through `Git::Url` and `Git::BranchName`, checks each field that
can reach git before a manifest enters the store; `Output.plain`, `CLI::Style.plain` and
`Git::Url.redact` treat what is printed; and `Plan` and the git errors quote each word they put
into a command printed for the user to run. A change there keeps every promise or updates
SECURITY.md in the same pull request. `test/unit/conventions_test.rb` keeps the spawn and the
warning line in their one place, and `test/unit/reset_rule_test.rb` keeps the reset to its one
form and its one caller.

## One definition, four outputs

A `CLI::Command` is plain data: name, summary, description, section, examples, positionals,
options, subcommands, exit statuses, handler. The same object feeds

- parsing and validation (`Parser`, `Validator`),
- `slipway VERB --help` and `slipway help VERB` (`HelpRenderer`),
- `man/man1/slipway-VERB.1` (`Manpage`, run by `bin/generate-man`),
- shell completion (`Completer`, answering `slipway __complete WORDS...` with cobra's directive
  protocol; the bash, zsh and fish scripts only relay that answer).

Nothing about a verb is written twice. Help text, option descriptions and examples live in the
verb's class (`DESCRIPTION`, `self.examples`, shared options in `Commands::Options`). What
belongs to no verb, the ENVIRONMENT, FILES, CONFIGURATION and EXIT STATUS sections of
slipway(1), lives in `Commands::Manual`, which `bin/generate-man` hands to `Manpage`; the
CONFIGURATION entries are `Config::DOCUMENTATION`, built from `Config::SETTINGS`.
`test/unit/seams_test.rb` derives the list of variables the code reads by scanning `lib/` and
compares it with `Commands::Manual::ENVIRONMENT`, so a new `env['X']` fails the test until it is
documented. `HOME` and `PATH` are the only variables read without a line in
the section; the test names them in an explicit allowlist. `test/unit/readme_test.rb` holds the
README variable table to the same keys.

## Adding things

**A verb.** Create `lib/slipway/commands/<verb>.rb` with a class under `Commands` inheriting
`Base`. Define `self.command(factory)` returning a `CLI::Command` (set `section:` to one of
`Basic Commands`, `Repository Commands`, `Settings Commands`, `Other Commands`; pass
`handler: new(factory)`) and `run(runtime, context, args, opts)`. A verb whose exit statuses
differ from the shared ones passes `exit_statuses:`, a Hash of status to meaning, which help
prints under the description and the man page renders as its EXIT STATUS section. Reuse
`Options::TYPE`, `Options.name_positional(factory)`, `Options::DRY_RUN` and friends; a verb that
acts on repositories takes `Options.project_positional(factory)` and reads it with
`Scope#project_targets`. Require the file in `commands.rb` and add the class to `VERBS` in help
order; `test/unit/commands/registry_test.rb` asserts that order and fails when a
`Commands::Base` subclass is reachable from `VERBS` neither directly nor as a subcommand of a
group. Print results through `result_line` (`project/hldr created`), or through
`Commands::Results` for a verb that prints one outcome per repository, and warnings through
`Output.warning`, and raise `Slipway::Error` or `CLI::UsageError` rather than writing to
stderr. Run `rake generate` so the new man page and help fixture land in `man/man1` and
`test/fixtures/golden`.

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

**A sync action.** Name the drift in `Drift` (its type in `TYPES`, and in `MOVES` when it
changes a working tree) with its message and, for a refusal, a `BLOCKERS` sentence built with
`Drift.blocker`. `Plan::Planner` decides when the action applies and which obstacles block it;
it reads only the inspection it is given, so its tests need no repository. Only
`Sync::Executor` performs the action, through a `Git::Repository` method, inside
`Fetcher#exclusively` and with its own reflog action. The action reports a result word in
`Commands::Sync::ROLES` whose role exists in both themes. It keeps every promise in
[SECURITY.md](SECURITY.md#safety-promises), or updates that list in the same pull request.

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
  `staged`, `unstaged`, `untracked`, `synced`, `ahead`, `behind`, `diverged`, `detached`,
  `unborn`, `conflicted`, `gone`, `stash`, `plain_dir`, and `stale`, `stale_untracked_overlap`
  and `index_lock`, whose origin holds a commit only a fetch reveals) with a pinned environment and
  dates, so the same recipe yields the same commit ids on every machine. The git adapter and
  the inspector are unit-tested against the same fixtures with the real `git`.
  `readme_examples_test.rb` runs the console examples of the README from top to bottom on the
  repositories `ReadmeStory` builds and compares what each command prints with the lines under
  it, once times, commit ids and ages in seconds are normalized.
- Golden tests under `test/golden` compare the help page of every command, the three completion
  scripts and the man pages with the files under `test/fixtures/golden` and `man/man1`, and
  `test/unit/cli/manpage_test.rb` compares two pages of a test registry with `test/fixtures/man`;
  `rake generate` refreshes all three after an intended change. `ShellHarness` also drives
  the completion scripts inside real shells (bash always; zsh and fish when installed, or
  unconditionally when `SLIPWAY_REQUIRE_SHELLS` is set, which the CI `completions` job does)
  against a stub program that answers `__complete` from a `FixtureRegistry`.

Convention tests sit next to the unit tests: `test/unit/conventions_test.rb` (layering, the
single git spawner, YAML writer and warning writer, no direct stdout or stderr, no runtime
dependencies, the files the gem ships, ASCII), `test/unit/reset_rule_test.rb` (`reset --keep` as
the only reset and `Rollback` as its only caller), `test/unit/changelog_test.rb` (the shape of
`CHANGELOG.md`), `test/unit/readme_test.rb` (the README tables and configuration example
against the code) and `test/unit/contributing_test.rb` (the task table in CONTRIBUTING against
the tasks the Rakefile and `rakelib/` define).
Tests for the development code live under `test/unit/dev`. The commit tests run git in
temporary repositories; the release and GitHub tests never run git or `gh` and hand the code a
fake command runner.

## Generated artifacts

The man pages under `man/man1` and the golden fixtures are generated and committed;
[CONTRIBUTING.md](CONTRIBUTING.md#generated-files) says what each one holds, how
`rake generate` refreshes them and what catches a stale one. `rake generate` renders the pages
through `bin/generate-man`, and the golden manpage test reads the page date through
`rakelib/support/changelog.rb`, the rule `bin/generate-man` applies, so the test and the
generator cannot disagree. `slipway man` reads the pages from the gem's own `man/man1`, which is
why they are committed and shipped; `.gitattributes` marks them `linguist-generated`.

## Development code

The Rakefile keeps the test, RuboCop, audit and documentation tasks. Everything else a
maintainer runs lives in `rakelib/`: `check.rake`, `generate.rake`, `package.rake`,
`shells.rake`, `release.rake` and `github.rake`, which Rake loads on its own, and plain Ruby
under `rakelib/support/` that the tasks and the scripts in `bin/` share (`changelog.rb` parses
and cuts the changelog, `release.rb` runs the release flow behind an injectable command runner,
`commits.rb` holds the commit rules `bin/lint-commits` applies and the range `rake check` hands
it, `github.rb` wraps `gh api`).
`rakelib/` is covered by RuboCop and the conventions test, and the gemspec excludes it, so none
of it ships in the gem.
