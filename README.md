# slipway

A kubectl-style registry for the git repositories on your machine.

[![CI](https://github.com/hvpaiva/slipway/actions/workflows/ci.yml/badge.svg)](https://github.com/hvpaiva/slipway/actions/workflows/ci.yml)

Slipway keeps a registry of the development projects on your machine and shows their git
state the way kubectl shows a cluster. You register a repository once, and from then on
`slipway get projects` tells you which ones are clean, dirty, ahead of their upstream or
gone from disk. The shape is borrowed on purpose: verbs and resource types (`get projects`,
`describe group work`), labels and selectors (`-l lang=rust`), groups as namespaces (`-n work`,
`-A`), manifests you can `apply -f`, and table, json or yaml output. If you already know
kubectl, you already know slipway. Slipway is deliberately small and complete in what a CLI
ships with: help, man pages, shell completion, a config file, and colors that respect
`NO_COLOR` and the terminal.

```console
$ slipway create group personal --description "Personal projects"
group/personal created

$ slipway create project hldr --path '~/dev/hldr' -n personal --label lang=rust --description "Site and CLI for hvpaiva.dev" --remote git@github.com:hvpaiva/hldr.git --branch main
project/hldr created

$ slipway create project augur --path '~/dev/augur' -n personal --label lang=bash
project/augur created

$ slipway create project notes --path '~/dev/notes' --label kind=docs
project/notes created

$ slipway get projects -A
GROUP      NAME    BRANCH   STATUS   FETCHED   AGE
default    notes   main     Ahead    2d        0s
personal   augur   main     Dirty    <never>   1s
personal   hldr    main     Clean    5h        1s

$ slipway get projects -n personal -o wide
NAME    BRANCH   STATUS   FETCHED   AGE   PATH          HEAD      LAST-COMMIT
augur   main     Dirty    <never>   1s    ~/dev/augur   8f9cdbb   11h
hldr    main     Clean    5h        1s    ~/dev/hldr    e001395   32h

$ slipway describe project augur -n personal
Name:         augur
Group:        personal
Labels:       lang=bash
Created:      2026-09-29T07:15:35Z
Age:          1s
Path:         ~/dev/augur
Description:  <none>
Remote:       <none>
Branch:       <none>
Revision:     <none>
Sync Policy:  FastForward
Paused:       false
Status:       Dirty
Repository:
  Branch:      main
  Head:        8f9cdbb
  Upstream:    <none>
  Ahead:       <none>
  Behind:      <none>
  Staged:      0
  Unstaged:    1
  Untracked:   1
  Conflicted:  0
  Stashes:     0
  Remote:      <none>
  Last Fetch:  <never>
Last Commit:
  Hash:     8f9cdbbc5ff8982322347d8e6a76ea3ab8821b51
  Author:   Highlander <contact@hvpaiva.dev>
  Date:     2026-09-28T20:15:35Z
  Subject:  refactor: split history reader
```

The paths are quoted so the shell leaves the `~` alone: slipway expands it itself, which keeps
the stored manifest portable between machines.

## Installation

```sh
gem install slipway
```

Slipway needs Ruby 3.4 or newer and git 2.35 or newer on `PATH` (older git runs but always
reports `Stashes: 0`, and git before 2.41 fetches without listing the refs that moved). It has no
runtime gem dependencies. To install from a checkout:

```sh
bundle install
bundle exec rake install
```

## Usage

| Verb | What it does |
| --- | --- |
| `get TYPE [NAME...]` | List resources as a table, or as wide, json, yaml or name output. |
| `describe TYPE [NAME...]` | Print every field of the selected resources, including the repository state. |
| `create TYPE NAME` | Register a project (`--path DIR`, `--description`, `--label`, `--remote`, `--branch`) or create a group. |
| `apply -f FILE` | Create or update resources from manifests; prints `created`, `configured` or `unchanged`. |
| `delete TYPE NAME...` | Remove registrations; deleting a group removes the registrations of its projects. |
| `edit TYPE NAME` | Open the manifest in your editor and save what comes back. |
| `label TYPE NAME KEY=VALUE...` | Set or remove labels on a resource. |
| `fetch [NAME...]` | Run `git fetch` in the selected projects, without prompts; prints `fetched`, `unchanged`, `skipped`, `paused`, `denied` or `failed`. |
| `config view`, `config path` | Show the configuration in effect and the file it came from. |
| `completion SHELL` | Print the completion script for bash, zsh or fish. |
| `man [COMMAND]` | Open the bundled manual page of a command. |
| `version` | Print the version, the Ruby it runs on and the platform, as `slipway 0.1.0 (ruby 4.0.7) [x86_64-linux]`. |
| `help [COMMAND]` | Print the same text as `--help`. |

Two resource types exist: `projects` (also `project`, `proj`) and `groups` (also `group`).
`slipway VERB --help` describes each verb.

### Groups

Projects live in groups the way pods live in namespaces. `-n NAME` (`--group`) selects one,
`-A` (`--all-groups`) lists across all of them and adds a GROUP column. Without either, the
`default` group is used, or the one set by `SLIPWAY_GROUP` or the `group` config key. The
default group is created the first time a write needs it; every other group has to be created
first, and `slipway delete group default` is refused.

### Selectors

`-l EXPR` (`--selector`) filters by labels with kubectl's grammar. Equality:

```console
$ slipway get projects -A -l lang=rust
GROUP      NAME   BRANCH   STATUS   FETCHED   AGE
personal   hldr   main     Clean    5h        1s
```

Set-based:

```console
$ slipway get projects -A -l 'lang in (rust,bash)'
GROUP      NAME    BRANCH   STATUS   FETCHED   AGE
personal   augur   main     Dirty    <never>   1s
personal   hldr    main     Clean    5h        1s
```

`key!=value`, `key notin (a,b)`, `key` (exists) and `!key` (does not exist) work as well, and
comma-separated terms must all hold. Neither a selector nor `-A` can be combined with explicit
names.

`--field-selector EXPR` filters on the fields of the object `-o json` prints, with kubectl's
field grammar: `path=value` (or `path==value`) and `path!=value`, comma-separated, all of which
must hold.

```console
$ slipway get projects -A --field-selector status.state!=Clean
GROUP      NAME    BRANCH   STATUS   FETCHED   AGE
default    notes   main     Ahead    2d        0s
personal   augur   main     Dirty    <never>   1s
```

Projects support `metadata.name`, `metadata.group`, `spec.path`, `status.state`,
`status.branch` and `status.lastFetch`; groups support `metadata.name`. Values compare exactly,
case included, and `spec.path` is the path as registered (`~/dev/hldr`), not the expanded one.
`status.lastFetch` compares as the RFC 3339 time `-o json` prints. A field the object leaves out
compares as the empty value, so `status.branch=` selects the projects on a detached HEAD and
those git could not read; `status.lastFetch` compares as `never` instead, so
`status.lastFetch=never` selects the projects no fetch has reached, those whose last fetch
failed and those git could not read. A backslash escapes `\`, `,` and `=` inside a value. Like a
label selector, a field selector cannot be combined with explicit names.

### Output formats

`-o table` is the default. `-o wide` adds PATH, HEAD and LAST-COMMIT (the age of the last
commit) to projects and DESCRIPTION to groups. `-o json` and `-o yaml` print the manifest
plus a `status` section, as one object when a single name is given and as a `kind: List`
otherwise. `-o name` prints `project/hldr` lines. `--no-headers` drops the header row and
`--show-labels` appends a LABELS column with `lang=rust` style pairs. AGE is the time since
the resource was registered, in kubectl's units (`3s`, `4m12s`, `11h`, `2y319d`). FETCHED is the
time since the repository was last fetched, by slipway or by git itself and from any of its
worktrees, and reads `<never>` when no fetch has run there or the last one failed: git empties
`FETCH_HEAD` as a fetch starts, so a failed fetch leaves no time behind. `describe` shows the
same time as `Last Fetch` and json and yaml as `status.lastFetch`.

### Status words

STATUS is one word per project, chosen in this order of precedence:

| STATUS | Meaning |
| --- | --- |
| `Missing` | The registered path is not a directory on this machine. |
| `NotARepo` | The directory exists but no repository contains it. |
| `Unsafe` | git refused the repository because another user owns it (`safe.directory`). |
| `Conflicted` | The working tree has unmerged paths. |
| `Detached` | HEAD points at a commit rather than a branch. |
| `Unborn` | The branch has no commits yet. |
| `Dirty` | Staged, modified or untracked files are present. |
| `Gone` | An upstream is configured but its ref no longer exists, as of the last fetch (FETCHED). |
| `Diverged` | The branch is both ahead of and behind its upstream, as of the last fetch (FETCHED). |
| `Ahead` | Commits not yet pushed to the upstream. |
| `Behind` | Commits on the upstream not yet pulled, as of the last fetch (FETCHED). |
| `Clean` | Nothing to do. |
| `Unknown` | git could not answer: it is not installed, it did not finish within 10 seconds, or it failed for a reason slipway does not classify. Each distinct reason is printed once on stderr per run. |

`get` and `describe` never contact a remote, so the words that compare a branch with its
upstream are as fresh as the last fetch. `slipway fetch` refreshes them.

### Fetching

```console
$ slipway fetch -A
project/notes fetched
  origin/main 1c2d3e4..5f6a7b8
project/augur skipped (NoRemote)
  no upstream, no origin and no single remote to fetch from
project/hldr unchanged
3 projects: 1 fetched, 1 unchanged, 1 skipped
```

`slipway fetch` runs `git fetch` in the projects of the current group, in the projects named
(`hldr` or `project/hldr`, so `slipway get projects -o name | xargs slipway fetch` works), in
the ones `-l` selects, or with `-A` in every project. Git fetches from the remote of the
checked-out branch, else from the only remote, else from origin, as a `git fetch` typed in the
repository would: slipway passes no remote, and nothing from a manifest reaches git's arguments.
Git updates the refs the remote's fetch refspecs name (remote-tracking refs by default), tags and
`FETCH_HEAD`, never the checked-out branch or the working tree.
`slipway fetch -A && slipway get projects -A` shows every STATUS as of now.

Up to `parallel` projects (4 by default) fetch at once. Each prints one result, in the order the
projects are listed, as soon as it and every project before it are done:

| Result | Meaning |
| --- | --- |
| `fetched` | The remote moved refs. Up to five follow, as `origin/main a1b2c3d..e4f5a6b`, then `and N more`. |
| `unchanged` | The remote answered and had nothing new. |
| `skipped (Reason)` | No fetch ran: git could not read the repository (`Missing`, `NotARepo`, `Unsafe`, `Unknown`), git has no remote to pick because there is no upstream, no origin and either no remote or more than one (`NoRemote`), or its branch tracks a local branch (`LocalUpstream`). |
| `paused` | The manifest sets `spec.paused: true`, so no git command ran in the project. |
| `denied (AuthRequired)` | Git needed a password, a passphrase or a host key. Run the `git -C PATH fetch` printed below it once in a terminal to see what git needs. |
| `failed (Reason)` | The fetch ran past `networkTimeout` (`Timeout`), used a transport `protocols` leaves out (`ProtocolNotAllowed`), or git failed for another reason (`Unknown`). |

When more than one project ran, a count of the results closes the run on stderr. The exit
status is 1 when any project was denied or failed, once every line has printed. `--prune` also
removes the remote-tracking refs of branches deleted on the remote. `--dry-run=client` reads the
repositories as `get` does and prints `fetched (dry run)` for each project a fetch would reach,
without running `git fetch`.

Git never prompts during a fetch: slipway sets `GIT_TERMINAL_PROMPT=0`, points `GIT_ASKPASS` and
`SSH_ASKPASS` at `false`, and sets `SSH_ASKPASS_REQUIRE=force` so ssh never reads the terminal.
Your ssh configuration, `SSH_AUTH_SOCK` and credential helpers are used as they are. Only the
transports in `protocols` are allowed, a fetch that runs past `networkTimeout` is killed with
every process it started, submodules are not fetched, and gc, automatic maintenance and bundle
URIs are off. On Ctrl-C slipway stops the git processes it started and exits with status 130.

### Manifests

`slipway get project hldr -n personal -o yaml` prints the stored manifest followed by
`status`. Without the status, a Project and a Group look like this:

```yaml
kind: Project
metadata:
  name: hldr
  group: personal
  labels:
    lang: rust
  creationTimestamp: '2026-09-29T07:15:35Z'
spec:
  path: "~/dev/hldr"
  description: Site and CLI for hvpaiva.dev
  remote: git@github.com:hvpaiva/hldr.git
  branch: main
```

```yaml
kind: Group
metadata:
  name: personal
  labels: {}
  creationTimestamp: '2026-09-29T07:15:35Z'
spec:
  description: Personal projects
```

Names follow the RFC 1123 label rule (lowercase letters, digits and dashes, at most 63
characters) and labels follow the Kubernetes rules. `spec.path` is stored as written and
expanded against `HOME` when used, so `~/dev/hldr` means the same thing on every machine that
syncs the registry; quote it on the command line so the shell does not expand it first.
`metadata.group` defaults to the current group and `creationTimestamp` is set on creation.

The rest of a project's spec declares the state its repository is expected to be in. Every
field is optional, and one at its default is not written:

| Field | Meaning | Default |
| --- | --- | --- |
| `spec.remote` | The URL the `origin` remote is expected to have: `scheme://host/path` with `ssh`, `https`, `http`, `git` or `file`, or `[user@]host:path`, where the host is letters, digits, `.` and `-`, starting with a letter or digit. A password in the URL, or any user name over http and https, where it often carries a token, is refused; use a credential helper. | none |
| `spec.branch` | The branch expected to be checked out: letters, digits, `.`, `_`, `/` and `-`, starting with a letter or digit. | none |
| `spec.revision` | The commit the project is expected to be at, as a full object name of 40 or 64 lowercase hexadecimal characters; an abbreviation is refused because it can become ambiguous. | none |
| `spec.syncPolicy` | `FastForward` allows the checked-out branch to be fast-forwarded onto its upstream; `FetchOnly` allows fetching only. | `FastForward` |
| `spec.paused` | `true` keeps `fetch` away from the project, which prints `project/NAME paused` and runs no git command there. | `false` |

Only `fetch` acts on one of these fields: it leaves a project with `spec.paused: true` alone. No
command compares a repository with the other four or changes it to match them, and STATUS does
not take them into account. The fields are checked whenever a manifest is read, and a value
that breaks its rule is refused with that rule, so nothing that could reach git as an option or
carry a control character is accepted. `describe`, `-o json` and `-o yaml` show them.

`slipway apply -f FILE` reads every YAML document in the file, `-f DIR` reads every `*.yaml`
and `*.yml` file in the directory sorted by name (without descending), and `-f -` reads stdin.
`-f` may be repeated. Each document prints `project/hldr created`, `configured` or
`unchanged`; problems are collected and printed as `error: FILE[:N]: ...` after the successes,
with exit status 1. `--dry-run=client` reports what would change without writing.

### Editing

`slipway edit project hldr -n personal` writes the manifest to a temporary file, opens it in
`SLIPWAY_EDITOR`, then the `editor` config key, then `VISUAL`, then `EDITOR`, or `vi`, and
saves what comes back as `project/hldr edited`. Text that changes without changing the object
prints `project/hldr skipped`. An unchanged file prints `Edit cancelled, no changes made.` on
stderr; an invalid one is reopened with the failure as a comment block at the top, and saving
that reopened file unchanged aborts with `error: Edit cancelled, no valid changes were saved.`;
an empty file aborts with `error: Edit cancelled, saved file was empty.`. Both aborts exit
with status 1.

### Labels

`slipway label project hldr tier=web -n personal` sets a label and prints
`project/hldr labeled`; `tier-` removes one (`unlabeled`). Setting a key that already has a
different value fails unless `--overwrite` is given: with `tier=web` set,
`slipway label project hldr tier=api -n personal` prints
`error: 'tier' already has a value (web), and --overwrite is false`. `--list` prints the labels
one `key=value` per line instead of writing.

## Configuration

Settings are resolved in this order: command-line flags, then `SLIPWAY_*` environment
variables, then the config file, then the built-in defaults. The file lives at
`$XDG_CONFIG_HOME/slipway/config.yaml` (`~/.config/slipway/config.yaml`) unless `--config PATH`
or `SLIPWAY_CONFIG` names another one. It is optional, and every key in it is optional:

```yaml
# ~/.config/slipway/config.yaml
color: auto              # auto, always or never
theme: light             # dark or light
editor: code --wait
group: personal          # used when -n is not given
networkTimeout: 60       # seconds before a git network command is killed
parallel: 4              # git network commands at once, from 1 to 16
protocols: [ssh, https]  # transports git may use; add file for local mirrors
```

`slipway config view` prints the values in effect with the file path as a comment on the
first line; `slipway config path` prints the path alone. An unknown key or a wrong value is an
error naming the file. `protocols` refuses `ext` and `fd` even when listed: `ext` runs a command
named in the URL, and `fd` reads from file descriptors.

| Variable | Effect |
| --- | --- |
| `SLIPWAY_CONFIG` | Path of the configuration file; `--config` outranks it. |
| `SLIPWAY_DATA_HOME` | Directory holding the registry. |
| `SLIPWAY_COLOR` | `auto`, `always` or `never`; `--color` outranks it. |
| `SLIPWAY_THEME` | `dark` or `light`. |
| `SLIPWAY_EDITOR` | Editor for `edit`; outranks the config key, `VISUAL` and `EDITOR`. |
| `SLIPWAY_GROUP` | Group used when `-n` is not given. |
| `SLIPWAY_NETWORK_TIMEOUT` | Seconds a git network command may run before it is killed. |
| `SLIPWAY_PARALLEL` | How many git network commands run at once, from 1 to 16. |
| `SLIPWAY_PROTOCOLS` | Transports git may use in network commands, separated by colons: `ssh:https`. |
| `SLIPWAY_DEBUG` | When non-empty, unexpected errors also print their class and backtrace. |
| `NO_COLOR` | When non-empty, disables color in `auto` mode. |
| `FORCE_COLOR` | When non-empty, enables color in `auto` mode even on a pipe. |
| `CLICOLOR_FORCE` | Same as `FORCE_COLOR`. |
| `VISUAL` | Editor for `edit` when `SLIPWAY_EDITOR` and the `editor` config key are unset. |
| `EDITOR` | Editor for `edit` when `VISUAL` is unset as well. |
| `XDG_CONFIG_HOME` | Base of the configuration directory (default `~/.config`). |
| `XDG_DATA_HOME` | Base of the data directory (default `~/.local/share`). |
| `TERM` | `dumb` turns color off in `auto` mode. |
| `MANPAGER` | When non-empty, `slipway man` leaves the pager palette alone. |
| `MANROFFOPT` | Same as `MANPAGER`. |
| `LESS_TERMCAP_md` | Same as `MANPAGER`. |
| `GROFF_NO_SGR` | Same as `MANPAGER`. |

The registry is a directory of plain YAML files under `$SLIPWAY_DATA_HOME`, by default
`$XDG_DATA_HOME/slipway` (`~/.local/share/slipway`):

```
groups/<group>.yaml
projects/<group>/<name>.yaml
```

Each file is the manifest shown above and nothing else is stored, so the directory can be
backed up, versioned or synced between machines. To rebuild a registry from a copy, apply
`groups/` first and then each `projects/<group>/` directory:
`slipway apply -f copy/groups -f copy/projects/personal`.

## Colors

`--color[=auto|always|never]` decides per stream; a bare `--color` means `always`. In `auto`
mode (the default) a non-empty `NO_COLOR` turns color off, then a non-empty `FORCE_COLOR` or
`CLICOLOR_FORCE` turns it on, then `TERM=dumb` turns it off, and otherwise stdout and stderr
are colored only when they are terminals. `SLIPWAY_COLOR` or the `color` key set the mode
without a flag. Two themes exist, `dark` (default) and `light`, selected with `SLIPWAY_THEME`
or the `theme` key. The palette follows kubecolor's defaults: bold headers, cycling column
colors, green for `Clean`, yellow for the states that need a push or a commit, red for the
ones that need attention.

## Shell completion

`slipway completion SHELL` prints the script; the header of each script says where it goes.

```sh
# bash: load it in the current session, or add the line to ~/.bashrc
eval "$(slipway completion bash)"
# bash: install it for bash-completion to load on demand
slipway completion bash > "${XDG_DATA_HOME:-$HOME/.local/share}/bash-completion/completions/slipway"

# zsh: put _slipway in a directory on your fpath (fpath+=~/.zfunc before compinit), or source it directly
slipway completion zsh > ~/.zfunc/_slipway
source <(slipway completion zsh)

# fish
slipway completion fish > ~/.config/fish/completions/slipway.fish
```

Completion covers commands, flags, flag values (`-o js<TAB>` gives `json`), resource types and
the names of your projects and groups, asked from the program itself each time you press TAB.

## Manual pages

The pages ship with the gem. `slipway man` opens `slipway(1)` and `slipway man get` opens
`slipway-get(1)` with `man(1)`, colored like the help page when color is on; if any of
`MANPAGER`, `MANROFFOPT`, `LESS_TERMCAP_md` or `GROFF_NO_SGR` is non-empty, your pager
settings win and slipway passes nothing of its own.

`slipway man --install` copies the pages to `${XDG_DATA_HOME:-~/.local/share}/man/man1` (a
relative `XDG_DATA_HOME` is ignored), and `slipway man --install=DIR` copies them into DIR,
which must be named `man1`: `man` finds section 1 pages in the `man1` directory under each
`MANPATH` entry, so any other DIR is refused with exit status 2. DIR is optional, so it must
follow the `=`; `slipway man --install DIR` is refused as well. When the pages land in
`~/.local/share/man/man1`, man-db looks there on its own as long as `~/.local/bin` is on
`PATH`, and the command ends by saying so. Anywhere else, such as under a custom
`XDG_DATA_HOME`, it ends with the `MANPATH` line for the parent directory, which makes `man`
find the pages. To read them without installing:

```sh
export MANPATH="$(dirname "$(slipway man --path)"):$MANPATH"
man slipway-get
```

`slipway help COMMAND` and `slipway COMMAND --help` print the same content in the terminal.

## Exit status

| Status | Meaning |
| --- | --- |
| `0` | Success. |
| `1` | Runtime error, such as a missing resource or an unreadable manifest. |
| `2` | Usage error: unknown command, unknown flag or invalid argument. |
| `130` | Interrupted by SIGINT. |

## Development

`bin/setup` installs the development dependencies and reports the tools it found.
`bundle exec rake` runs the tests and RuboCop, the fast loop; `bundle exec rake check` runs
what CI runs. CI (`.github/workflows/ci.yml`) runs the tasks of `rake check` as separate jobs,
plus what a single machine cannot: the Ruby 3.4 and macOS entries of the test matrix and the
completion scripts in real zsh and fish. It also lints the commits of every pull request and
checks spelling, the workflows and the links in the guides. The tasks defined under `rakelib/`
are development tasks and are not part of the gem.

| Task | Runs |
| --- | --- |
| `rake test`, `test:unit`, `test:integration` | Minitest with Ruby warnings on: everything under `test/`, or one of `test/unit` and `test/integration`. |
| `rake test:cov` | The unit and golden tests under SimpleCov, failing below the line and branch minimums set in the Rakefile. |
| `rake test:shells` | The completion script tests with zsh and fish required, locally when both are installed, otherwise with docker in an image built from `ruby:4.0`. |
| `rake rubocop` | RuboCop with the minitest, performance and rake plugins. |
| `rake audit` | Updates the advisory database and checks `Gemfile.lock` with bundler-audit. |
| `rake check` | `rubocop`, `lint:shell`, `lint:man`, `lint:commits`, `test:cov`, `test:integration`, `generate:check`, `package:check` and `audit`, in that order; `CHECK_OFFLINE=1` skips the audit. |
| `rake generate`, `generate:man`, `generate:golden` | `generate:man` renders the man pages, then `lint:man` lints them, then `generate:golden` rewrites the help, completion and man page fixtures and removes the help and completion ones no command owns; `generate` runs the three and prints `git status` for `man`, `test/fixtures/golden` and `test/fixtures/man`. |
| `rake generate:check` | Renders the man pages into a temporary directory and fails when `man/man1` differs. |
| `rake lint:man` | `groff -man -ww` over `man/man1` with an empty stderr. |
| `rake lint:shell` | ShellCheck over `bin/setup` and the bash completion script. |
| `rake lint:commits` | `bin/lint-commits` over `origin/main..HEAD`; on `main`, or without `origin/main`, it says so and lints nothing. |
| `rake package:check` | Builds the gem, installs it into a temporary `GEM_HOME` and runs the installed `slipway` (`version`, `--help`, `man --path`, and ShellCheck over its bash completion). |
| `rake release:verify` | Checks a release tag against `Slipway::VERSION` and `CHANGELOG.md`; run by the Release workflow. |
| `rake release:guard_ci` | Aborts unless running inside GitHub Actions; `rake release`, `rake release:source_control_push` and `rake release:rubygem_push` run it before they tag or push. |
| `rake github:setup` | Configures the GitHub repository (merge commits only, release environment, rulesets, security alerts, immutable releases, the `skip-changelog` label) through `gh api`, idempotently. |
| `rake docs` | YARD documentation. |
| `rake build`, `rake install` | The bundler gem tasks. |
| `rake release` | The publish step `release.yml` runs through `rubygems/release-gem`; refused locally. Use `bin/release` instead. |

`man/man1`, `test/fixtures/golden` and `test/fixtures/man` are generated: `rake generate`
rewrites the pages from the command definitions, dating them from the newest release heading in
`CHANGELOG.md` (no date while there is none), and refreshes the fixtures. CI regenerates the
pages and fails when the committed ones are stale. The completion scripts are printed at run
time and are not generated files.

## Other documents

- [CONTRIBUTING.md](CONTRIBUTING.md) for the development workflow, conventions and the release process.
- [ARCHITECTURE.md](ARCHITECTURE.md) for a map of the code.
- [CHANGELOG.md](CHANGELOG.md) for what changed in each version.
- [SECURITY.md](SECURITY.md) for how to report a vulnerability.
- [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) for the rules of the community.

## License

MIT. See [LICENSE.txt](LICENSE.txt).
