# Architecture

A map of the code for maintainers. The user-facing behavior is in [README.md](README.md) and
the man pages; this file explains where things live and why they are shaped the way they are.

## Layers

Everything is under `lib/slipway`, loaded by `lib/slipway.rb`, with no runtime gem dependencies.

| Layer | Files | What lives there |
| --- | --- | --- |
| Command layer | `cli.rb`, `cli/` | `Registry`, `Command`, `Glossary`, `Option`, `Positional` and `Example` (the data model), `Globals`, `Parser`, `Validator`, `Runner` (the front controller), `HelpRenderer`, `Manpage`, `Completer`, `CompletionScripts`, `Builtins`, `Context`, `Style`, `Theme` and `UsageError`. It knows nothing about projects or git. |
| Domain | `error.rb`, `version.rb`, `yaml.rb`, `resources.rb`, `schema.rb`, `manifest.rb`, `store.rb`, `names.rb`, `labels.rb`, `selector.rb`, `field_selector.rb`, `settings.rb`, `paths.rb`, `editor.rb`, `scanner.rb` | `Slipway::Error`, `VERSION`, `Yaml`, `Project` and `Group`, `Schema`, `Manifest`, `Store`, `Names`, `Labels`, `Selector`, `FieldSelector`, `Settings`, `Paths`, `Editor` and `Scanner` (the search behind `create project --from-dir`). |
| Git adapter | `git.rb`, `git/`, `state.rb` | `Git::Runner`, `Git::Repository` with its `FastForwarding` and `RollingBack` parts, the answers (`Status` and `Porcelain`, `Commit`, `FetchResult`, `Reflog`, `Distance`, `FastForward`, `MoveBack`), `Url`, `BranchName`, the errors in `git/errors.rb`, `Git::Fake`, and `State`. |
| Reconciliation | `drift.rb`, `plan.rb`, `command_line.rb`, `rollout_history.rb` | `Drift`, `Plan`, `CommandLine` (the git command lines slipway prints and never runs) and `RolloutHistory`. |
| Output | `output.rb`, `output/` | `Output.plain` and `Output.warning`, `Table`, `Describe` and `Painted`, `Explain`, `Serializer` (json, and yaml through `Yaml`) and `Age`. |
| Views | `views.rb`, `views/` | `Views::Project` and `Views::Group`. |
| Commands and runtime | `slipway.rb`, `commands.rb`, `commands/`, `runtime.rb`, `inspector.rb`, `fetcher.rb`, `outcome.rb`, `syncer.rb`, `rollback.rb`, `pool.rb` | One class per verb, `Commands::Options`, `Scope`, `Results` and `Manual`, `Runtime`, `Inspector` and its `Inspection`, `Fetcher`, `Outcome` (the result of one project and the words several verbs print), `Syncer`, `Rollback` and `Pool`. |

The domain holds the rules for what may enter the registry and how it is stored: `Store` writes
each manifest as a plain file, `Manifest` parses and checks one, and `Yaml` writes every YAML
document slipway stores or prints. `Git::Repository` holds every git argv slipway runs and asks
the questions slipway needs, `Git::Runner` spawns git ([Running git](#running-git)), and `State`
reduces a status or an error to the one STATUS word. `Git::Fake` answers the same questions from
canned entries for the command tests; it sits under `lib/` next to the class it stands in for,
so the layering rule and the coverage gates apply to it, and `test/unit/git/fake_test.rb` holds
its methods to the repository's.

`Schema` is the manifest contract, written once: for each kind, every field with its type,
description, default, rule and whether it is required. The reader in `Manifest` refuses any field
`Schema` does not name and takes its defaults and the words of its refusals from there; `Names`,
`Labels`, `Git::Url` and `Git::BranchName` check their fields with the rules `Schema` quotes.
`explain` prints it, and the README table of a project's spec gives the same meanings and
defaults, which `test/unit/readme_test.rb` compares in both directions.

`Plan.for` reads one `Inspection` into the drift sync would resolve, the drift it leaves alone
and the blockers that stop it. It runs no git and reads no file, so `get -o wide`, `describe`,
`diff` and `sync` read the same answer, and its tests need no repository. A `spec.revision` pin
replaces the upstream as where the branch should be, reached only forward and only along the
upstream. `RolloutHistory` numbers the revisions of a branch from the reflog entries whose
subject starts with `slipway `, and the commits the branch stood at before those moves.

Output renders plain data through a `Context` and never touches resources. Views turn a
resource, or an `Inspection`, into table rows, describe entries and the object hash json and
yaml print, and list in `FIELDS` the paths of that hash a field selector may name; they do no
I/O. `Runtime` bundles the settings, paths, store, git, inspector and clock of one run.

A verb's class under `Commands` takes the verb's name, as `Commands::Sync` does, and a class
directly under `Slipway` that a verb drives is named for what it does or holds (`Fetcher`,
`Syncer`, `Rollback`, `RolloutHistory`, `Settings`, `Plan`), so a bare `Sync` inside `Commands`
always means the command.

Dependencies point one way: commands use the runtime, views and output; views use the domain,
the git values, the plan and output; output paints through the command layer's `Context`. The
command layer and the domain (with the git adapter and reconciliation) sit at the bottom:
neither requires commands, views, the runtime, the inspector, the fetcher, the syncer, the
rollback, the `Outcome` they report or the pool. The command layer requires one domain file, the
one allowed edge: `cli/errors.rb` requires `error.rb`, because `CLI::UsageError` is a
`Slipway::Error`. The domain may use the command layer: `labels.rb`, `selector.rb` and
`field_selector.rb` raise `CLI::UsageError`, and `settings.rb` validates against `CLI::Theme`
and `CLI::Style`. `test/unit/conventions_test.rb` reads every `require_relative` under `lib/`,
fails on an edge that breaks these rules and on a file that belongs to no layer or to two, and
`test/unit/require_graph_test.rb` loads every file under `lib/` on its own.

## One invocation

`exe/slipway` calls `Slipway.run(ARGV)`. From there:

1. `Commands.registry(factory)` builds the `CLI::Registry`: the verbs in `Commands::VERBS`,
   each built by its class's `self.command(factory)`, plus the builtins (`help`, `version`,
   `completion`, `man`, hidden `__complete`).
2. `Runtime.color_defaults` peeks at `--config` in argv and reads the config file once, so the
   `color` and `theme` keys can act as fallbacks before any option is parsed.
3. `CLI::Runner#execute` scans argv for `--color` before anything is parsed, so even an error
   in the parse is painted the way the user asked. It then walks the command tree. Global
   options may appear before the verb, between a group and its subcommand, and after the verb
   (`Parser#order!` while walking, `#permute!` on the leaf). `--help`, `--version` and a bare
   group name return early.
4. `Validator` checks arity, positional enums, required options and option enums, raising
   `UsageError` (exit 2) with a `See 'slipway get --help' for usage.` hint.
5. The command's handler is an instance of `Commands::Base`. `call` asks the factory for a
   `Runtime` (`Runtime.build` in production, a hand-built one in tests) and hands off to `run`.
6. `Commands::Scope` resolves the type word, the group in effect, `-A` and the selector, then
   reads from the `Store`. For projects, `Inspector#examine_all` runs `Git::Repository` per path
   (`#examine` for one) and `State.derive` names the state. A field selector is matched after
   that, on the object hash json prints, because some of its fields are what git answered.
7. `Views` turn the results into rows or entries, `Output` renders them through the `Context`,
   whose two `Style` objects decide color for stdout and stderr separately. A verb that prints
   one result per repository calls `Context#unbuffer` first, so each line reaches a pipe before
   the count on stderr. Ruby also flushes stdout before every spawn, so a line a closed pipe
   refused would otherwise stay in the buffer and fail each later git with `EPIPE`.
8. The `Context` remembers a stream whose reader went away and drops what is written to it
   afterwards, so a command whose stdout `head` closed still finishes its work and exits with
   its own status. `Runner#execute` maps what escapes the command: a `Slipway::Error` prints
   one `error: MESSAGE` line per entry of its `problems`, then its hint line when it has one
   (the help pointer of a `UsageError`, the git command that trusts an `Unsafe` repository),
   and exits with its `exit_status`, 1 unless the class says otherwise (2 for `UsageError`, 3
   for diff's `Differs`). An error with no problems, such as `Commands::Fetch::Failed`, exits 1
   without a line, because the result lines already said what failed. `Interrupt` exits 130,
   and any other `StandardError` exits 1, with class and backtrace added when `SLIPWAY_DEBUG`
   is set. An `Errno::EPIPE` raised past the `Context` reaches `Runner#run` and exits 0.

## Running git

`Git::Runner#run` is the one place that spawns git; [SECURITY.md](SECURITY.md#how-git-runs)
states what that promises to users, and this section says how the code keeps it.

- The child's environment is the caller's `env:` merged under `Runner::ENVIRONMENT`, so a caller
  can add variables but cannot change `LC_ALL=C`, the disabled prompt and optional locks, or
  the repository-selecting variables `ENVIRONMENT` unsets. `CEILING_VARIABLE`
  (`GIT_CEILING_DIRECTORIES`) is set to the real parent of the registered directory, since git
  compares real paths when it climbs.
- Git starts with `-C` and the absolute directory, in a process group of its own, with standard
  input closed. A reader thread drains each of stdout and stderr, so a chatty command cannot
  fill a pipe and stall.
- The deadline is `DEFAULT_TIMEOUT` (10 seconds) for a local command and the `timeout:` a
  network command passes, `networkTimeout`. It covers the pipes as well as git, because a helper
  git started can hold a pipe open after git exits.
- Git is stopped at the deadline and whenever the block unwinds for another reason, such as an
  interrupt or the `Thread#kill` of a pool worker: TERM to the whole group, `TERM_GRACE` for git
  to remove its lock files, then KILL, then the reader threads are killed. `Errno::ESRCH` and
  `Errno::EPERM` from a signal mean nothing is left to signal (macOS answers EPERM for a group
  that exited but is not reaped) and are ignored, so they never replace the exception that is
  ending the run.
- Interrupts are held from before the spawn until the `ensure` that stops git is armed, so an
  interrupt landing between the two cannot leave git running.
- `run` returns a `Result` whatever git's exit status is, with a death by signal N read as 128+N
  (`SIGNAL_STATUS_BASE`) and the output scrubbed to valid UTF-8. A binary that cannot start
  raises `NotInstalled`, and the deadline `Timeout`.

`Git::Repository#run` sits on top. It raises `MissingPath` for a path that is not a directory
without spawning, returns the result when git succeeded or when `accept:` says the failure is an
answer (a key `git config` lacks, a branch with no commits), and raises the classified error
otherwise. `test/unit/git/runner_test.rb`, `runner_stop_test.rb` and `runner_session_test.rb`
pin these rules, and `test/integration/fetch_process_test.rb` checks that an interrupt during a
fetch exits with 130 and leaves no git behind.

## Network commands

Every git command that may contact a remote runs under one profile: `fetch`, the fast-forward
(`FastForwarding#merge`) and the rollout move (`RollingBack#reset`), which in a partial clone
fetch the objects they write. A new command that may contact a remote goes through
`Repository#network_fetch` or passes the same `network: true`, `timeout: @network_timeout` and
`env: @network_environment` to `run`, never a bare `run`. The profile is:

- `Runner.network_environment(protocols)`: `Runner::NETWORK_ENVIRONMENT`, which points
  `GIT_ASKPASS` and `SSH_ASKPASS` at `false` and sets `SSH_ASKPASS_REQUIRE=force`, plus
  `GIT_ALLOW_PROTOCOL` joined from the `protocols` setting. Once that variable is set it is
  git's whole transport policy and git's own refusal of `ext` no longer applies, which is why
  `Settings` refuses `ext` and `fd` (`Settings::UNSAFE_PROTOCOLS`) even when listed.
- `Runner::NETWORK_CONFIG`: no gc, no automatic maintenance and no bundle URI download.
- The `networkTimeout` deadline.

`Repository#fetch` passes no remote argument (`FETCH_ARGS`), so git picks the remote a
`git fetch` typed in the repository would, and nothing from a manifest reaches its argv. Two
checks run locally first: `local_upstream?` raises `LocalUpstream` for a branch that tracks
another local branch, and `Fetcher` asks `default_remote?` (`git ls-remote --get-url`, which
contacts nothing) only when neither an origin nor an upstream settles which remote git would
use. The fetch then asks for `--porcelain`, which git learned in 2.41; an older git rejects it
as a usage error before it connects, the repository remembers that and fetches again without
it, and the `FetchResult` it returns has `updates` set to nil.

A network command's failure is classified by `network_failure` only: `ProtocolNotAllowed` when
stderr is nothing but git's refusal of a transport, and `AuthRequired` when a line matches
`AUTH_REQUIRED`. The phrases that name a local failure are not read there, because ssh and the
remote write to the same stream. Anything else becomes a `Git::Error` quoting the first line of
stderr, redacted by `Git::Url.redact` before it is cut to `MESSAGE_LIMIT` characters.
`test/unit/git/repository_fetch_test.rb`, `repository_fetch_answers_test.rb`,
`repository_fetch_user_config_test.rb` and `test/unit/settings_network_test.rb` cover the
profile.

## Concurrency and interrupts

`Pool#map` and `Pool#each_ordered` run a block per item on at most `workers` threads and hand
the results back in input order. Callers follow its contract:

- The block runs on worker threads, so state it shares needs a lock. `Fetcher#exclusively`
  holds one lock per ref store, keyed by `Repository#common_dir`, so a linked worktree and its
  main one never fetch or move at once.
- An exception from an item is re-raised on the calling thread at once, without waiting for
  the other items. A caller therefore turns the failures it expects into results inside the
  block: `Inspector#examine` returns an `Inspection` with the error, and `Fetcher` an
  `Outcome`. What escapes is a bug or a fatal condition.
- However a call ends early, the pool kills and joins its workers before the exception leaves
  it, and killing a thread runs its `ensure` blocks, where `Git::Runner` stops the git it
  started.

There are two pool sizes. `Inspector` reads repositories on a fixed `DEFAULT_WORKERS` (8)
threads: a read is local, and the `parallel` setting paces network commands only.
`Commands::Results` runs the work of `fetch` and `sync` on `parallel` threads and prints each
result through `each_ordered` as soon as every earlier one is done.
`Syncer` splits sync in two: its workers inspect, fetch through `Fetcher`, inspect
again and plan, and the calling thread fast-forwards each project as its result comes up,
inside `Fetcher#exclusively`, so no two of its writes run at once. `Rollback` runs on the
calling thread for its one project and is the only caller of the move back.

Ctrl-C raises `Interrupt` in the main thread. The pool's `ensure` kills its workers, each
runner's `ensure` stops its process group, and `CLI::Runner#execute` writes a line feed to
stderr, so the shell prompt starts on its own line, and returns 130. `test/unit/pool_test.rb`,
`test/unit/syncer_test.rb` and `test/integration/fetch_process_test.rb` pin this.

## Printing untrusted text

Every table cell, describe value and `result_line` name passes `Output.plain`, which makes
control and bidirectional characters visible, and so do the fields git answered in json and
yaml output. The detail lines under a result pass `Output.plain(Git::Url.redact(...))` in
`Commands::Results#report`. Warning lines are written only by `Output.warning`, which passes
the message through the same rule. The runner's error and hint lines pass it through
`CLI::Style.plain`; only a `UsageError` takes `layout: true`, which keeps the line feeds and
tabs of a "Did you mean this?" list. A remote URL git reports passes `Git::Url.redact`, and a
git failure keeps only the first line of git's stderr, redacted and cut to 200 characters.
`spec.remote` is refused, from `--remote` or a manifest, whenever redact would change it, so
json and yaml print it as stored. [SECURITY.md](SECURITY.md#output) states the rule for users.

One known limit: json and yaml print the other manifest fields as stored too, and `spec.path`
and `spec.description` have no rule against control characters, so a tool such as `jq -r`
passes them to the terminal. SECURITY.md names it.

## Safety promises

[SECURITY.md](SECURITY.md#safety-promises) lists what slipway promises about the git it runs,
the writes to a working tree, the environment git gets and what reaches the terminal. A few
places keep those promises: `Git::Runner` spawns every git process and sets its environment;
`Git::Repository` holds every git argv, its `FastForwarding` part the fast-forward, which only
`Syncer` and `Rollback` call, and its `RollingBack` part the reset, which only
`Rollback` calls; `Manifest`, through `Git::Url` and `Git::BranchName`, checks each field that
can reach git before a manifest enters the store; `Output.plain`, `CLI::Style.plain` and
`Git::Url.redact` treat what is printed; and `Plan` and the git errors quote each word they put
into a command printed for the user to run. `CommandLine` quotes the path of such a command and
joins the other words as its caller gives them. A change there keeps every promise or updates
SECURITY.md in the same pull request. `test/unit/conventions_test.rb` keeps git's spawn in the
runner and the warning line in its one place, and `test/unit/reset_rule_test.rb` keeps the reset
to its one form and its one caller.

## One definition, four outputs

A `CLI::Command` is plain data: name, summary, description, section, examples, positionals,
options, subcommands, exit statuses, glossaries (`CLI::Glossary`, a titled list of terms such as
the columns or result words a verb prints), handler. The same object feeds

- parsing and validation (`Parser`, `Validator`),
- `slipway VERB --help` and `slipway help VERB` (`HelpRenderer`),
- `man/man1/slipway-VERB.1` (`Manpage`, run by `bin/generate-man`),
- shell completion (`Completer`, answering `slipway __complete WORDS...` with cobra's directive
  protocol; the bash, zsh and fish scripts only relay that answer, and the bash one keeps the
  function and variable names of cobra's bash script, by which ble.sh finds the descriptions).

Nothing about a verb is written twice. Help text, option descriptions and examples live in the
verb's class (`DESCRIPTION`, `self.examples`, shared options in `Commands::Options`). What
belongs to no verb, the ENVIRONMENT, FILES, CONFIGURATION and EXIT STATUS sections of
slipway(1), lives in `Commands::Manual`, which `bin/generate-man` hands to `Manpage`; the
CONFIGURATION entries are `Settings::DOCUMENTATION`, built from `Settings::ALL`, and the
ENVIRONMENT line of each setting's variable points at its entry instead of describing the value
again. `test/unit/seams_test.rb` derives the list of variables the code reads by scanning `lib/`
and compares it with `Commands::Manual::ENVIRONMENT`, so a new `env['X']` fails the test until
it is documented. `HOME` and `PATH` are the only variables read without a line in the section;
the test names them in an explicit allowlist. `test/unit/readme_test.rb` holds the README
variable table to the same keys.

## Adding things

**A verb.** Create `lib/slipway/commands/<verb>.rb` with a class under `Commands` inheriting
`Base`. Define `self.command(factory)` returning a `CLI::Command` (set `section:` to one of
`Basic Commands`, `Repository Commands`, `Settings Commands`, `Other Commands`; pass
`handler: new(factory)`) and `run(runtime, context, args, opts)`. A verb whose exit statuses
differ from the shared ones passes `exit_statuses:`, a Hash of status to meaning, which help
prints under the description and the man page renders as its EXIT STATUS section; a verb that
prints words a reader needs explained passes `glossaries:`. Reuse `Options::TYPE`,
`Options.name_positional(factory)`, `Options::DRY_RUN` and friends; a verb that acts on
repositories takes `Options.project_positional(factory)` and reads it with
`Scope#project_targets`. A verb that acts on resources overrides `kinds` with the
`Resources::Kind` values it accepts, which is how `api-resources -o wide` lists it under VERBS.
Require the file in `commands.rb` and add the class to `VERBS` in help order;
`test/unit/commands/registry_test.rb` asserts that order, holds a verb that takes a TYPE to every
kind and one that takes only project names to projects, and fails when a `Commands::Base`
subclass is reachable from `VERBS` neither directly nor as a subcommand of a group. Print results
through `result_line` (`project/hldr created`), or through `Commands::Results` for a verb that
prints one outcome per repository, and warnings through `Output.warning`, and raise
`Slipway::Error` or `CLI::UsageError` rather than writing to stderr. A verb that reads nothing
from the machine, as `explain` reads only `Schema`, skips `Base` and the runtime, so a broken
configuration file cannot stop it: its class defines `self.command(factory)` and its handler
responds to `call(context, args, opts)` and to `kinds`. Run `rake generate` so the new man page
and help fixture land in `man/man1` and `test/fixtures/golden`, add the verb's row to the README
Usage table and a line to `CHANGELOG.md`. A new file outside the directories
`conventions_test.rb` lists goes into exactly one of its layer lists, and every file under `lib/`
must load on its own.

**An option.** Add a `CLI::Option` (`long:`, optional `short:`, `argument:` for a value,
`enum:` for a closed set, `default:`, `repeatable:`, `required:`, `optional:` plus `implicit:`
for `--flag[=VALUE]`) to the command's `options:`. Read it in `run` as `opts[:long_name]`
(`--no-headers` becomes `opts[:no_headers]`). Help, the man page and completion pick it up;
an `enum` is also its completion list.

**A completer.** Give an `Option` or `Positional` a `completer:` proc. It receives the
positional words typed so far and the word being completed, and returns an Array of values, a
Hash of value to description, `CLI::Completer::FILES` to hand the shell its file completion, or
`CLI::Completer::DIRS` for directory names only.
Values wrapped in `CLI::Completer::NoSpace` ask the shell to add no space after the one it
inserts, for a value the user goes on typing, such as a path extended one segment at a time.
The directive covers the whole answer, so such a completer filters by the word itself and wraps
its values only when a match goes on. `Options.name_positional` shows the pattern for values
that need the store: build the runtime through the factory, and return `[]` on any error,
because a completion must never fail in the shell.

**A manifest field.** Add a `Schema::Field` under its kind in `Schema`, with its type,
description, `rule` or `enum`, default and whether it is required; until then the reader refuses
it as unknown. Add the member to `Project` or `Group` and to its `to_manifest`, in the order the
schema gives, which `test/unit/store/schema_test.rb` compares, and read it in the reader in
`Manifest`, with the default and the words of its refusals taken from the field. A value that can
reach git goes through a check such as `Git::Url` or `Git::BranchName`, whose rule the field
quotes. `explain` prints the field as it is; one in a project's spec also gets its row in the
README table, which `readme_test.rb` holds to the schema.

**A theme role.** Add the role to `CLI::Theme::DARK` (and to the `LIGHT` merge when the light
value differs), as an SGR parameter string or an Array for roles cycled by index. Paint with
`context.paint(:role, text)` or `context.style.paint_cycle(:role, index, text)`. The theme test
holds a copy of both presets and `seams_test.rb` checks that every `State::ROLES` entry exists
in both themes.

**A sync action.** Name the drift in `Drift` (its type in `TYPES`, and in `MOVES` when it
changes a working tree) with its message and its line in `TYPE_MEANINGS` and, for a refusal, a
`BLOCKERS` sentence built with `Drift.blocker` and a line in `BLOCKER_MEANINGS`; the README
tables follow both. `Plan::Planner` decides when the action applies and which obstacles block
it; it reads only the inspection it is given, so its tests need no repository. Only
`Syncer` performs the action, through a `Git::Repository` method, inside
`Fetcher#exclusively` and with its own reflog action. The action reports a result word in
`Commands::Sync::ROLES` whose role exists in both themes, and the verb's Results
glossary explains it. It keeps every promise in [SECURITY.md](SECURITY.md#safety-promises), or
updates that list in the same pull request.

**A setting.** Add a `Settings::Setting` to `Settings::ALL` with its key, `SLIPWAY_*` variable,
default, description, check and expectation, and `parse:` when the variable is not read as a
plain string; add the member to the `Settings` Data. The description becomes its CONFIGURATION
entry in slipway(1). Add the variable to `Commands::Manual::ENVIRONMENT` through its `setting`
helper, which `seams_test.rb` requires, and the key to the README configuration example and the
variable to the README table, which `readme_test.rb` requires. Read the value from
`runtime.settings`, and run `rake generate`.

**A git question.** Add a public method to `Git::Repository`, or to `FastForwarding` or
`RollingBack` for a move, that runs git through the private `run`, with the network profile
when it may contact a remote ([Network commands](#network-commands)), and never through
`Git::Runner` directly. Pass `accept:` for a failure that is an answer, and name a new failure
in `git/errors.rb` and in `local_failure` or `network_failure`. Give `Git::Fake` the same
method with the same parameters, which `test/unit/git/fake_test.rb` requires, and test the real
one against a `GitFixtures` repository, adding a state to `GitFixtures#build_repo` when none
has what the question needs.

**A selectable field.** Add its path to `Views::Project::FIELDS` or `Views::Group::FIELDS`,
with the value it compares as when the object leaves it out. The path must be one of the object
`-o json` prints. The `--field-selector` help lists the fields from `FIELDS`; add the field to
the README sentence that lists them, which `readme_test.rb` holds to `FIELDS`, and to the field
selector line in `CHANGELOG.md`.

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
  against a stub program that answers `__complete` from a `FixtureRegistry`;
  `test/unit/cli/completion_ble_test.rb` replays in plain bash what ble.sh does with the bash
  script.

Convention tests sit next to the unit tests: `test/unit/conventions_test.rb` (layering, the two
files that spawn processes, the YAML writer, the warning writer, no direct stdout or stderr, no
runtime dependencies, the files the gem ships, ASCII, test file names),
`test/unit/require_graph_test.rb` (every file under `lib/` loads on its own),
`test/unit/seams_test.rb` (the variables the code reads against the man page, and the constants
two layers must agree on), `test/unit/reset_rule_test.rb` (`reset --keep` as the only reset and
`Rollback` as its only caller), `test/unit/changelog_test.rb` (the shape of `CHANGELOG.md`),
`test/unit/readme_test.rb` (the README tables and configuration example against the code) and
`test/unit/contributing_test.rb` (the task table in CONTRIBUTING against the tasks the Rakefile
and `rakelib/` define).
Tests for the development code live under `test/unit/dev`. The commit tests run git in
temporary repositories; the release and GitHub tests never run git or `gh` and hand the code a
fake command runner; the sandbox test runs `bin/sandbox` itself, with `TMPDIR`, `HOME` and
`XDG_DATA_HOME` in a temporary directory.

## Generated artifacts

The man pages under `man/man1` and the golden fixtures are generated and committed;
[CONTRIBUTING.md](CONTRIBUTING.md#generated-files) says what each one holds, how
`rake generate` refreshes them and what catches a stale one. `rake generate` renders the pages
through `bin/generate-man`, and the golden manpage test reads the page date through
`rakelib/support/changelog.rb`, the rule `bin/generate-man` applies, so the test and the
generator cannot disagree. `slipway man` reads the pages from the gem's own `man/man1`, which is
why they are committed and shipped; `.gitattributes` marks them `linguist-generated`.

## Development code

The Rakefile keeps the test, coverage, RuboCop, audit and documentation tasks, `generate:man`,
`lint:man`, `lint:shell`, `lint:spelling`, `lint:workflows` and `lint:links`, and `require_tool`,
which stops a task that needs a missing program and which `rakelib/package.rake` calls too.
Everything else a maintainer runs lives in `rakelib/`: `check.rake`, `generate.rake`,
`package.rake`, `shells.rake`, `release.rake` and `github.rake`, which Rake loads on its own, and
plain Ruby under `rakelib/support/` that the tasks and the scripts in `bin/` share: `changelog.rb`
parses and cuts the changelog, `commits.rb` holds the commit rules `bin/lint-commits` applies and
the range `rake check` hands it, `golden.rb` lists the fixtures `generate:golden` keeps,
`release.rb` runs the release flow, `github.rb` wraps `gh api`, `tools.rb` reads the tools
`mise.toml` pins, the list `bin/setup` installs, and words the message `require_tool` gives for a
missing one, and `runner.rb` holds `CommandRunner`, the command runner `bin/release` and
`rake github:setup` inject so their tests can pass a fake.
`rakelib/` is covered by RuboCop and the conventions test, and the gemspec excludes it, so none
of it ships in the gem. `bin/setup` and `bin/sandbox` are bash, checked by ShellCheck through
`rake lint:shell`.
