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

$ slipway create project hldr --path '~/dev/hldr' -n personal --label lang=rust --description "Site and CLI for hvpaiva.dev"
project/hldr created

$ slipway create project augur --path '~/dev/augur' -n personal --label lang=bash
project/augur created

$ slipway create project notes --path '~/dev/notes' --label kind=docs
project/notes created

$ slipway get projects -A
GROUP      NAME    BRANCH   STATUS   AGE
default    notes   main     Ahead    0s
personal   augur   main     Dirty    1s
personal   hldr    main     Clean    1s

$ slipway get projects -n personal -o wide
NAME    BRANCH   STATUS   AGE   PATH          HEAD      LAST-COMMIT
augur   main     Dirty    1s    ~/dev/augur   8f9cdbb   11h
hldr    main     Clean    1s    ~/dev/hldr    e001395   32h

$ slipway describe project augur -n personal
Name:         augur
Group:        personal
Labels:       lang=bash
Created:      2026-09-29T07:15:35Z
Age:          1s
Path:         ~/dev/augur
Description:  <none>
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
reports `Stashes: 0`). It has no runtime gem dependencies. To install from a checkout:

```sh
bundle install
bundle exec rake install
```

## Usage

| Verb | What it does |
| --- | --- |
| `get TYPE [NAME...]` | List resources as a table, or as wide, json, yaml or name output. |
| `describe TYPE [NAME...]` | Print every field of the selected resources, including the repository state. |
| `create TYPE NAME` | Register a project (`--path DIR`, `--description`, `--label`) or create a group. |
| `apply -f FILE` | Create or update resources from manifests; prints `created`, `configured` or `unchanged`. |
| `delete TYPE NAME...` | Remove registrations; deleting a group removes the registrations of its projects. |
| `edit TYPE NAME` | Open the manifest in your editor and save what comes back. |
| `label TYPE NAME KEY=VALUE...` | Set or remove labels on a resource. |
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
GROUP      NAME   BRANCH   STATUS   AGE
personal   hldr   main     Clean    1s
```

Set-based:

```console
$ slipway get projects -A -l 'lang in (rust,bash)'
GROUP      NAME    BRANCH   STATUS   AGE
personal   augur   main     Dirty    1s
personal   hldr    main     Clean    1s
```

`key!=value`, `key notin (a,b)`, `key` (exists) and `!key` (does not exist) work as well, and
comma-separated terms must all hold. Neither a selector nor `-A` can be combined with explicit
names.

### Output formats

`-o table` is the default. `-o wide` adds PATH, HEAD and LAST-COMMIT (the age of the last
commit) to projects and DESCRIPTION to groups. `-o json` and `-o yaml` print the manifest
plus a `status` section, as one object when a single name is given and as a `kind: List`
otherwise. `-o name` prints `project/hldr` lines. `--no-headers` drops the header row and
`--show-labels` appends a LABELS column with `lang=rust` style pairs. AGE is the time since
the resource was registered, in kubectl's units (`3s`, `4m12s`, `11h`, `2y319d`).

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
| `Gone` | An upstream is configured but its ref no longer exists. |
| `Diverged` | The branch is both ahead of and behind its upstream. |
| `Ahead` | Commits not yet pushed to the upstream. |
| `Behind` | Commits on the upstream not yet pulled. |
| `Clean` | Nothing to do. |
| `Unknown` | git could not answer: it is not installed, it did not finish within 10 seconds, or it failed for a reason slipway does not classify. Each distinct reason is printed once on stderr per run. |

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

`slipway apply -f FILE` reads every YAML document in the file, `-f DIR` reads every `*.yaml`
and `*.yml` file in the directory sorted by name (without descending), and `-f -` reads stdin.
`-f` may be repeated. Each document prints `project/hldr created`, `configured` or
`unchanged`; problems are collected and printed as `error: FILE[:N]: ...` after the successes,
with exit status 1. `--dry-run=client` reports what would change without writing.

### Editing

`slipway edit project hldr` writes the manifest to a temporary file, opens it in
`SLIPWAY_EDITOR`, then the `editor` config key, then `VISUAL`, then `EDITOR`, or `vi`, and
saves what comes back as `project/hldr edited`. Text that changes without changing the object
prints `project/hldr skipped`. An unchanged file prints `Edit cancelled, no changes made.` on
stderr; an invalid one is reopened with the failure as a comment block at the top, and saving
that reopened file unchanged aborts with `error: Edit cancelled, no valid changes were saved.`;
an empty file aborts with `error: Edit cancelled, saved file was empty.`. Both aborts exit
with status 1.

### Labels

`slipway label project hldr tier=web` sets a label and prints `project/hldr labeled`;
`tier-` removes one (`unlabeled`). Setting a key that already has a different value fails with
`error: 'tier' already has a value (web), and --overwrite is false` unless `--overwrite` is
given. `--list` prints the labels one `key=value` per line instead of writing.

## Configuration

Settings are resolved in this order: command-line flags, then `SLIPWAY_*` environment
variables, then the config file, then the built-in defaults. The file lives at
`$XDG_CONFIG_HOME/slipway/config.yaml` (`~/.config/slipway/config.yaml`) unless `--config PATH`
or `SLIPWAY_CONFIG` names another one. It is optional, and every key in it is optional:

```yaml
# ~/.config/slipway/config.yaml
color: auto        # auto, always or never
theme: light       # dark or light
editor: code --wait
group: personal    # used when -n is not given
```

`slipway config view` prints the values in effect with the file path as a comment on the
first line; `slipway config path` prints the path alone. An unknown key or a wrong value is an
error naming the file.

| Variable | Effect |
| --- | --- |
| `SLIPWAY_CONFIG` | Path of the configuration file; `--config` outranks it. |
| `SLIPWAY_DATA_HOME` | Directory holding the registry. |
| `SLIPWAY_COLOR` | `auto`, `always` or `never`; `--color` outranks it. |
| `SLIPWAY_THEME` | `dark` or `light`. |
| `SLIPWAY_EDITOR` | Editor for `edit`; outranks the config key, `VISUAL` and `EDITOR`. |
| `SLIPWAY_GROUP` | Group used when `-n` is not given. |
| `SLIPWAY_DEBUG` | When non-empty, unexpected errors also print their class and backtrace. |
| `NO_COLOR` | When non-empty, disables color in `auto` mode. |
| `FORCE_COLOR` | When non-empty, enables color in `auto` mode even on a pipe. |
| `CLICOLOR_FORCE` | Same as `FORCE_COLOR`. |
| `VISUAL`, `EDITOR` | Editor for `edit` when nothing above names one. |
| `XDG_CONFIG_HOME` | Base of the configuration directory (default `~/.config`). |
| `XDG_DATA_HOME` | Base of the data directory (default `~/.local/share`). |

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
`slipway-get(1)` with `man(1)`. `slipway man --install` copies them to
`${XDG_DATA_HOME:-~/.local/share}/man/man1`, where man-db looks when `~/.local/bin` is on
`PATH`; `slipway man --install=DIR` copies them into DIR instead and prints the `MANPATH` line
that makes `man` find them there. To read them without installing:

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

`bin/setup` installs the development dependencies and `bundle exec rake` runs the tests and
RuboCop. CI runs those plus the lint, audit, coverage, generated-files, package and completion
jobs in `.github/workflows/ci.yml`; the tasks they call are listed below.

| Task | Runs |
| --- | --- |
| `rake test`, `test:unit`, `test:integration` | Minitest with Ruby warnings on: everything under `test/`, or one of `test/unit` and `test/integration`. |
| `rake test:cov` | The unit and golden tests under SimpleCov, failing below the line and branch minimums set in the Rakefile. |
| `rake rubocop` | RuboCop with the minitest, performance and rake plugins. |
| `rake audit` | Updates the advisory database and checks `Gemfile.lock` with bundler-audit. |
| `rake generate` | Regenerates every generated file (`generate:man`). |
| `rake lint:man` | `groff -man -ww` over `man/man1` with an empty stderr. |
| `rake lint:shell` | ShellCheck over `bin/setup` and the bash completion script. |
| `rake docs` | YARD documentation. |
| `rake build`, `rake install`, `rake release` | The bundler gem tasks. |

`man/man1` is generated: `rake generate` rewrites the pages from the command definitions,
dating them from the newest release heading in `CHANGELOG.md`. CI regenerates them and fails
when the committed pages are stale. The completion scripts are printed at run time and are not
generated files.

## Other documents

- [CONTRIBUTING.md](CONTRIBUTING.md) for the development workflow, conventions and the release process.
- [ARCHITECTURE.md](ARCHITECTURE.md) for a map of the code.
- [CHANGELOG.md](CHANGELOG.md) for what changed in each version.
- [SECURITY.md](SECURITY.md) for how to report a vulnerability.
- [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) for the rules of the community.

## License

MIT. See [LICENSE.txt](LICENSE.txt).
