# slipway

A kubectl-style registry of the git repositories on your machine: it shows where each one stands
against its upstream and its manifest, and fast-forwards the ones that can move safely.

[![CI](https://github.com/hvpaiva/slipway/actions/workflows/ci.yml/badge.svg)](https://github.com/hvpaiva/slipway/actions/workflows/ci.yml)

`slipway get projects` shows in one table which of the git repositories you registered are clean,
dirty, behind their upstream or missing from disk, and `slipway fetch` fetches them all without
ever stopping at a password prompt. Each registration is a manifest that can also declare where
its repository should be, such as the remote, the branch or a commit to hold it at: `slipway diff`
shows how each repository differs from that, `slipway sync` fast-forwards the branches that can
move without losing anything, and `slipway rollout undo` takes such a move back.

Three repositories are cloned under `~/dev`. Register them, two in a `personal` group and one in
the `default` group:

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
```

STATUS is read from the repository on disk, so it is as fresh as the last fetch, whose age
FETCHED shows. Fetching every project brings in what was pushed from other machines since:

```console
$ slipway fetch -A
project/notes fetched
  origin/main 1c2d3e4..5f6a7b8
project/augur skipped (NoRemote)
  no upstream, no origin and no single remote to fetch from
project/hldr fetched
  origin/main e001395..4c5d6e7
3 projects: 2 fetched, 1 skipped

$ slipway get projects -A
GROUP      NAME    BRANCH   STATUS     FETCHED   AGE
default    notes   main     Diverged   0s        1s
personal   augur   main     Dirty      <never>   1s
personal   hldr    main     Behind     0s        1s
```

hldr is now behind `origin/main`, and notes, which had a commit of its own, has diverged from
it. `diff` compares each repository with its manifest and says what `sync` would do, and `sync`
does it:

```console
$ slipway diff -A
project/notes
  Behind: 1 commit behind origin/main
  Diverged: 1 ahead, 1 behind origin/main; sync never merges or rebases
    git -C ~/dev/notes log --oneline --left-right HEAD...@{upstream}
project/augur
  NoUpstream: main tracks no upstream; sync fast-forwards only a tracking branch
project/hldr
  Behind: 3 commits behind origin/main; sync will fast-forward

$ slipway sync -A
project/notes skipped (Diverged)
  1 ahead, 1 behind origin/main; sync never merges or rebases
  git -C ~/dev/notes log --oneline --left-right HEAD...@{upstream}
project/augur skipped (NoRemote)
  no upstream, no origin and no single remote to fetch from
project/hldr fast-forwarded
  main e001395..4c5d6e7 (3 commits); undo with 'slipway rollout undo project/hldr -n personal'
3 projects: 1 fast-forwarded, 2 skipped
```

A move you did not want is undone with the command printed under it:

```console
$ slipway rollout undo project/hldr -n personal
project/hldr rolled back
  main 4c5d6e7..e001395 (3 commits back to revision 1); held there by spec.revision
  'slipway rollout unpin project/hldr -n personal' follows origin/main again
```

The command line follows kubectl: verbs over resource types, groups used the way kubectl uses
namespaces (`-n personal`, `-A`), label selectors (`-l lang=rust`), manifests you can
`apply -f`, and table, json or yaml output. STATUS words, drift and the result lines of
`fetch`, `sync` and `rollout` are slipway's own, and the sections below define each of them.

## Installation

Slipway is not published on RubyGems yet. Until it is, install it from a checkout:

```sh
git clone https://github.com/hvpaiva/slipway.git
cd slipway
bundle install
bundle exec rake install
```

Once it is published, `gem install slipway` installs it, and so does `mise use -g gem:slipway`
with [mise](https://mise.jdx.dev).

Slipway needs Ruby 3.4 or newer and git 2.35 or newer on `PATH`, and has no runtime gem
dependencies. Git before 2.41 cannot tell `unchanged` from `fetched`, so every fetch that
succeeds reads `fetched`, without the refs that moved. Fetching over ssh without a prompt needs
OpenSSH 8.4 or newer; an older ssh may still ask on the terminal.

## Usage

| Verb | What it does |
| --- | --- |
| `get TYPE [NAME...]` | List resources as a table, or as wide, json, yaml or name output. |
| `describe TYPE [NAME...]` | Print every field of the selected resources, including the repository state. |
| `create TYPE NAME` | Register a project (`--path DIR`, `--description`, `--label`, `--remote`, `--branch`) or create a group; `-o yaml` prints the manifest. |
| `create project --from-dir DIR` | Register every git repository at or under a directory, with its origin URL. |
| `apply -f FILE` | Create or update resources from manifests; prints `created`, `configured` or `unchanged`. |
| `delete TYPE NAME...` | Remove registrations and print `project "hldr" deleted from personal group`; the repository on disk is not touched. Deleting a group removes the registrations of its projects. `--ignore-not-found` turns a name that does not exist into a success. |
| `edit TYPE NAME` | Open the manifest in your editor and save what comes back. |
| `label TYPE NAME KEY=VALUE...` | Set or remove labels on a resource. |
| `fetch [NAME...]` | Run `git fetch` in the selected projects, without prompts; prints `fetched`, `unchanged`, `skipped`, `paused`, `denied` or `failed`. |
| `diff [NAME...]` | Show where projects differ from their manifests, without contacting a remote; exit status 3 when any does. |
| `sync [NAME...]` | Fetch the selected projects and fast-forward each clean branch that is behind; prints `fast-forwarded`, `fetched`, `unchanged`, `skipped`, `paused`, `denied` or `failed`. |
| `rollout history NAME` | List the revisions slipway moved a project's branch to, read from the branch reflog. |
| `rollout undo NAME` | Move the branch back to the previous revision, or to `--to-revision=N`, and hold it there with `spec.revision`. |
| `rollout unpin NAME...` | Remove `spec.revision`, so `sync` follows the upstream again. |
| `rollout pause NAME...`, `rollout resume NAME...` | Set or remove `spec.paused`, which keeps `fetch` and `sync` away from a project. |
| `config view`, `config path` | Show the configuration in effect and the file it came from. |
| `completion SHELL` | Print the completion script for bash, zsh or fish. |
| `man [COMMAND]` | Open the bundled manual page of a command. |
| `api-resources` | List the resource types with their short names and kind, and whether they live in a group; `-o wide` adds the verbs that act on each. |
| `version` | Print the version, the Ruby it runs on and the platform, as `slipway 0.1.0 (ruby 4.0.7) [x86_64-linux]`. |
| `help [COMMAND]` | Print the same text as `--help`. |

Two resource types exist: `projects` (also `project`, `proj`) and `groups` (also `group`), and
type words are case-insensitive; `slipway api-resources` lists them
([Discovering resources](#discovering-resources)). A project is named bare (`hldr`) or as
`project/hldr`, the form `get -o name` prints. `create`, `apply`, `delete`, `label`, `fetch`,
`sync` and `rollout undo` accept `--dry-run`, which fetches and writes nothing and ends each
result line with `(dry run)`. `slipway VERB --help` describes each verb, `-h` prints help and
`-V` the version.

### Groups

Projects live in groups the way pods live in namespaces. `-n NAME` (`--group`) selects one,
`-A` (`--all-groups`) lists across all of them and adds a GROUP column. Without either, the
`default` group is used, or the one set by `SLIPWAY_GROUP` or the `group` config key. The
default group is created the first time a write needs it; every other group has to be created
first, and `slipway delete group default` is refused.

```console
$ slipway get groups
NAME       PROJECTS   AGE
default    1          1s
personal   2          1s

$ slipway describe group personal
Name:         personal
Labels:       <none>
Created:      2026-09-29T07:15:35Z
Age:          1s
Description:  Personal projects
Projects:     2
```

PROJECTS counts the projects registered in the group. `-o wide` adds DESCRIPTION, and
`--show-labels` adds LABELS for groups as it does for projects.

### Registering existing clones

`slipway create project --from-dir ~/dev/personal -n personal` registers every git repository
at or under the directory, searching `--depth` levels down (1 by default, at most 8). The search
stops at a directory with a `.git` entry, so a linked worktree counts and nothing nested inside
a repository does, and it never follows a symbolic link below the directory. Each project is
named after its directory, lowercased, with each run of characters other than ASCII letters,
digits and dashes made one dash (`My.Notes_v2` becomes `my-notes-v2`). `spec.path` starts with
`~/` under `HOME`, and `spec.remote` is the URL of `origin` without its credentials: the whole
user part over http and https, the password elsewhere. An origin that still breaks the
`spec.remote` rule, such as a local path, is left out with a `warning:` line. The checked-out
branch is not recorded, since it may be a feature branch; set `spec.branch` with `edit` when you
want it.

A path the group already holds prints `project/NAME unchanged`, whatever its name, so running
the command again registers only the new clones. A derived name that another path already has
is reported after the other lines, as `error: ~/dev/foo: project "foo" already exists at
~/dev/Foo`, with exit status 1. `--dry-run -o yaml` prints the projects as one
`kind: List` without writing anything, ready for `slipway apply -f` on another machine.

### Describing

`describe` prints the manifest, the repository as git reports it, the last commit and the
[drift](#drift). hldr, after the rollback above, is held at a commit its upstream has moved past:

```console
$ slipway describe project hldr -n personal
Name:         hldr
Group:        personal
Labels:       lang=rust
Created:      2026-09-29T07:15:35Z
Age:          1s
Path:         ~/dev/hldr
Description:  Site and CLI for hvpaiva.dev
Remote:       git@github.com:hvpaiva/hldr.git
Branch:       main
Revision:     e001395 (pinned)
Sync Policy:  FastForward
Paused:       false
Status:       Behind
Repository:
  Branch:      main
  Head:        e001395
  Upstream:    origin/main
  Ahead:       0
  Behind:      3
  Staged:      0
  Unstaged:    0
  Untracked:   0
  Conflicted:  0
  Stashes:     0
  Remote:      git@github.com:hvpaiva/hldr.git
  Last Fetch:  2026-09-29T07:15:35Z
Last Commit:
  Hash:     e001395f1c8d1b0e8a7c0c56f7b0e1a4b3c2d1e0
  Author:   Highlander <contact@hvpaiva.dev>
  Date:     2026-09-27T23:15:35Z
  Subject:  feat: list posts by year
Drift:        <none>
```

STATUS compares the branch with its upstream and ignores the pin, while drift compares the
repository with the manifest, so hldr is Behind with no drift. When git cannot read the
repository, the Repository block holds git's reason instead of the fields.

### Labels

```console
$ slipway label project hldr tier=web -n personal
project/hldr labeled

$ slipway label project hldr tier=web -n personal
project/hldr not labeled

$ slipway label project hldr tier=api -n personal
error: 'tier' already has a value (web), and --overwrite is false

$ slipway label project hldr --list -n personal
lang=rust
tier=web

$ slipway label project hldr tier- -n personal
project/hldr unlabeled
```

`KEY=VALUE` sets a label and `KEY-` removes one. A key that already has a different value is
changed only with `--overwrite`. `not labeled` means nothing changed: the label already had
that value, or the label to remove was not set.

### Editing

`slipway edit project hldr -n personal` writes the manifest to a temporary file, opens it in
`SLIPWAY_EDITOR`, then the `editor` config key, then `VISUAL`, then `EDITOR`, or `vi`, and
saves what comes back as `project/hldr edited`. Text that changes without changing the object
prints `project/hldr skipped`. An unchanged file prints `Edit cancelled, no changes made.` on
stderr; an invalid one is reopened with the failure as a comment block at the top, and saving
that reopened file unchanged aborts with `error: Edit cancelled, no valid changes were saved.`;
an empty file aborts with `error: Edit cancelled, saved file was empty.`. Both aborts exit
with status 1.

### Fetching

`slipway fetch` runs `git fetch` in the projects of the current group, in the projects named,
in the ones `-l` selects, or with `-A` in every project. Git fetches from the remote of the
checked-out branch, else from the only remote, else from origin, as a `git fetch` typed in the
repository would: slipway passes no remote, and nothing from a manifest reaches git's arguments.
Git updates the refs the remote's fetch refspecs name (remote-tracking refs by default), tags and
`FETCH_HEAD`, never the checked-out branch or the working tree. A second fetch right after the
one above finds nothing new:

```console
$ slipway fetch -A
project/notes unchanged
project/augur skipped (NoRemote)
  no upstream, no origin and no single remote to fetch from
project/hldr unchanged
3 projects: 2 unchanged, 1 skipped
```

Up to `parallel` projects (4 by default) fetch at once. Each prints one result, in the order the
projects are listed, as soon as it and every project before it are done:

| Result | Meaning |
| --- | --- |
| `fetched` | The remote moved refs. Up to five follow, then `and N more`: `origin/main a1b2c3d..e4f5a6b` for a ref that moved, `origin/feature d09a085 (new)` for a new one and `origin/feature deleted (was d09a085)` for one `--prune` removed. Tags appear under their bare name. |
| `unchanged` | The remote answered and had nothing new. |
| `skipped (Reason)` | No fetch ran: git could not read the repository (`Missing`, `NotARepo`, `Unsafe`, `Unknown`), git has no remote to pick because there is no upstream, no origin and either no remote or more than one (`NoRemote`), or its branch tracks a local branch (`LocalUpstream`). |
| `paused` | The manifest sets `spec.paused: true`, so no git command ran in the project. |
| `denied (AuthRequired)` | Git needed a password, a passphrase or a host key. Run the `git -C PATH fetch` printed below it once in a terminal to see what git needs. |
| `failed (Reason)` | The fetch ran past `networkTimeout` (`Timeout`), used a transport `protocols` leaves out (`ProtocolNotAllowed`), or git failed for another reason (`Unknown`). |

When more than one project ran, a count of the results closes the run on stderr. The exit
status is 1 when any project was denied or failed, once every line has printed.

`--prune` also removes the remote-tracking refs of branches deleted on the remote, and it is
what makes a branch whose upstream was deleted read `Gone`: a plain fetch leaves the old ref in
place, unless git's `fetch.prune` is set. To bring every STATUS up to date, whatever the fetch
reports:

```sh
slipway fetch -A --prune; slipway get projects -A
```

Git never prompts during a fetch: slipway sets `GIT_TERMINAL_PROMPT=0`, points `GIT_ASKPASS` and
`SSH_ASKPASS` at `false`, and sets `SSH_ASKPASS_REQUIRE=force`, so an ssh from OpenSSH 8.4 on
never reads the terminal.
Your ssh configuration, `SSH_AUTH_SOCK` and credential helpers are used as they are. Only ssh
and https remotes are fetched unless the `protocols` setting adds more, so an `http://`,
`git://` or local path remote fails with `ProtocolNotAllowed` until it does. A fetch that runs
past `networkTimeout` is killed with every process it started, submodules are not fetched, and
gc, automatic maintenance and bundle URIs are off. On Ctrl-C slipway stops the git processes it
started and exits with status 130.

### Diffing

`slipway diff` compares every project of the current group, the ones named, the ones a selector
matches, or with `-A` every project, with its manifest. Each project that differs prints its
name and one line per [drift](#drift) item, and an item that has a git command to show or
resolve it is followed by that command, as in the example at the top of this page. A project
that matches its manifest prints nothing. Slipway never runs these commands, never writes to a
repository or to the registry, and contacts no remote.

The exit status is 0 when every project matches its manifest and 3 when any differs or is
blocked, `NotARepo` and `Unsafe` included. It is 1 on an error, such as an unreadable manifest
or a project whose state is `Unknown`, so a script or a timer can tell drift from failure.

### Syncing

`slipway sync` fetches the projects of the current group, the ones named, the ones `-l` selects,
or with `-A` every project, as `slipway fetch` does. It then compares each one with its manifest
as `slipway diff` does and fast-forwards the checked-out branch onto its upstream with
`git merge --ff-only --no-autostash` when nothing blocks it: the branch has commits and tracks
an upstream that still exists, is behind it and not ahead of it, and has no staged, unstaged or
conflicted changes and no merge, rebase, cherry-pick, revert, bisect or `git am` in progress.
Untracked files do not block it; git refuses a fast-forward that would overwrite one, and sync
reports that. Sync never pulls, merges, rebases, stashes, resets, cleans, pushes, switches a
branch, changes a remote or removes a lock. [SECURITY.md](SECURITY.md#safety-promises) lists
every promise slipway makes about the repositories it touches.

| Result | Meaning |
| --- | --- |
| `fast-forwarded` | The branch moved. For a move onto the upstream, the detail names the commits it gained, as `main a1b2c3d..e4f5a6b (3 commits)`, and the command that undoes the move. |
| `fetched` | The fetch of a `FetchOnly` project moved refs; the refs follow as in `fetch`. |
| `unchanged` | The branch stayed where it was and nothing blocked it; the fetch may still have moved remote-tracking refs. |
| `skipped (Reason)` | The branch stayed where it was: a [blocker](#drift) stopped it, git refused the fast-forward (`WouldOverwrite` for untracked files in the way, `WouldLoseChanges` for local changes `git status` does not show, `Busy` for a lock another git process holds on the index, `HEAD` or the branch, `NotFastForward` for a branch that gained a commit since the check), or the project was skipped before its fetch as in `fetch`. |
| `paused` | The manifest sets `spec.paused: true`, so no git command ran in the project. |
| `denied (AuthRequired)` | The fetch or the fast-forward needed a password, a passphrase or a host key, as in `fetch`. |
| `failed (Reason)` | The fetch or the fast-forward ran past `networkTimeout` (`Timeout`), used a transport `protocols` leaves out (`ProtocolNotAllowed`), or git failed for another reason (`Unknown`). A fast-forward stopped at the deadline leaves the branch where it was, but the files git had already written stay in the working tree, and the detail names the command that lists them. |

A difference sync leaves alone, such as a `Remote` or a `Branch` [drift](#drift), and a branch
that `FetchOnly` keeps behind follow as detail lines. A project pinned by `spec.revision` is
fast-forwarded up to that commit, `main a1b2c3d..b2c3d4e (to the pinned revision)`, and then
stays there whatever its upstream brings. hldr, held by the rollback above, stays put:

```console
$ slipway sync hldr -n personal
project/hldr unchanged
  held at e001395 by spec.revision
```

A pin the repository lacks is skipped as `RevisionNotFound`, a HEAD past the pin as
`PastRevision`, and a pin its upstream does not hold, such as a commit on another branch or a
fork, as `OffUpstream`: a manifest can hold a project back but never send it where its upstream
has not been.

Up to `parallel` projects fetch at once, while fast-forwards run one at a time; each result prints
in the order the projects are listed, and a count of the results closes the run on stderr. Each
fast-forward leaves `slipway sync: Fast-forward` in the branch's reflog. The exit status is 1
when a fetch or a fast-forward was denied or failed, once every line has printed; a skipped
project never changes it, so a dirty tree does not fail the run. With `--dry-run`, sync
plans from the last fetch and warns about the projects no fetch has reached.

### Rolling back

Slipway undoes its own moves. Each fast-forward of `sync` runs with `GIT_REFLOG_ACTION` set to
`slipway sync` and each move of `rollout undo` with `slipway rollout undo`, so the branch's reflog
records them and slipway keeps no history of its own. `slipway rollout history NAME` lists them as
revisions, oldest first: every commit slipway moved the checked-out branch to, and the commit the
branch stood at before such a move.

```console
$ slipway rollout history hldr -n personal
REVISION   COMMIT    DATE                   CHANGE-CAUSE                   PINNED
1          e001395   2026-09-27T23:15:35Z   <none>                         false
2          4c5d6e7   2026-09-29T07:15:35Z   sync: fast-forward 3 commits   false
3          e001395   2026-09-29T07:15:35Z   rollout undo to revision 1     true

$ slipway rollout unpin hldr -n personal
project/hldr unpinned

$ slipway sync hldr -n personal
project/hldr fast-forwarded
  main e001395..4c5d6e7 (3 commits); undo with 'slipway rollout undo project/hldr -n personal'
```

CHANGE-CAUSE names the move and PINNED marks the revision `spec.revision` holds. `history`
fetches and writes nothing; a project without history prints
`No rollout history found for project/NAME.` on stderr and exits with 0.

`slipway rollout undo NAME` moves the checked-out branch to the revision before the current one,
or to the one `--to-revision=N` names, and then writes that commit to `spec.revision`, so `sync`
holds the project there. The manifest is written only after git moved the branch. A move back runs
`git reset --keep`, the one form of reset slipway ever runs, and only when the upstream holds every
commit the move drops; a move forward, which undoes an undo, runs `git merge --ff-only`. Untracked
files and unstaged changes to files the move leaves alone are kept. A move back needs an index
without staged changes, because `reset --keep` resets every index entry.

| Result | Meaning |
| --- | --- |
| `rolled back` | The branch moved, or it already stood at the revision and only `spec.revision` changed. The detail names the commits it crossed and the command that lets `sync` follow the upstream again. |
| `unchanged` | The branch already stood at the revision and `spec.revision` already held it. |
| `skipped (Reason)` | Nothing moved and nothing was written. The branch cannot move (`Conflicted`, `Detached`, `Unborn`, `NoUpstream`, `Gone`, `InProgress`); the history has no such revision (`NoHistory`, `NoPrevious`, `UnknownRevision`) or the repository no such commit (`RevisionNotFound`); a move back would drop commits the upstream lacks (`LocalCommits`) or staged changes (`Dirty`), or the revision is off the branch's history (`Diverged`); a move forward needs a tree without staged or unstaged changes (`Dirty`) and a revision on the upstream (`OffUpstream`); or git refused the move (`WouldLoseChanges`, `WouldOverwrite` for untracked or ignored files in the way, `Busy`, `NotFastForward` for a branch that moved since the check). |
| `denied (AuthRequired)` | A partial clone had to fetch the files the move writes and the remote asked for a password, a passphrase or a host key, as in `fetch`. |
| `failed (Reason)` | The move ran past `networkTimeout` (`Timeout`) or git failed for another reason (`Unknown`), and `spec.revision` was not written, though a move stopped at the deadline keeps the files git had already written, as in `sync`; or the branch moved but `spec.revision` could not be written (`NotPinned`), and the detail names the `--to-revision` command that writes it without moving the branch again. |

The exit status is 1 when the project was skipped, denied or failed.

`slipway rollout unpin NAME...` removes `spec.revision` and prints `unpinned`, or `not pinned`
when there was none; the next `sync` fast-forwards onto the upstream as usual.
`slipway rollout pause NAME...` sets `spec.paused` and `slipway rollout resume NAME...` removes
it, printing `paused` or `already paused` and `resumed` or `not paused`. None of the three runs
git. A paused project can still be rolled back: pausing keeps only `fetch` and `sync` away.

The history is the local reflog, so it lasts as long as git keeps it (`gc.reflogExpire`, 90 days
by default; slipway never runs `git gc`) and is empty when `core.logAllRefUpdates` is off. The pin
lives in the manifest and outlasts the reflog. Rollout moves commits only.

### Periodic fetch

`fetch` moves no branch and touches no working tree, so it can run on a timer that keeps
FETCHED current, and with it every STATUS word that compares a branch with its upstream. `sync`
is not meant for a timer: it moves checked-out branches, and a branch should not move under an
open editor or a half-done change unless you ask. A systemd user timer that fetches every
project once an hour:

```ini
# ~/.config/systemd/user/slipway-fetch.service
[Unit]
Description=Fetch every project in the slipway registry

[Service]
Type=oneshot
ExecStart=/path/to/slipway fetch -A
```

```ini
# ~/.config/systemd/user/slipway-fetch.timer
[Unit]
Description=Fetch every project in the slipway registry hourly

[Timer]
OnCalendar=hourly
RandomizedDelaySec=5m
Persistent=true

[Install]
WantedBy=timers.target
```

```sh
systemctl --user daemon-reload
systemctl --user enable --now slipway-fetch.timer
journalctl --user -u slipway-fetch.service
```

`ExecStart` takes an absolute path: replace `/path/to/slipway` with what `command -v slipway`
prints. The service runs with the environment of the systemd user manager, which
`systemctl --user show-environment` prints, not with your shell's: git has to be on its `PATH`,
and a `SLIPWAY_*` variable exported in your shell profile does not reach it, so put settings in
the config file or in `Environment=` lines of the service. `Persistent=true` runs a fetch the
timer missed while the machine was off as soon as the timer starts again. `journalctl` shows
the result lines of each run. A run in which a project was denied or failed exits with status 1,
and `systemctl --user status slipway-fetch.service` reports it as failed; a skipped project does
not fail the run.

The ssh client finds your agent through `SSH_AUTH_SOCK`, which the user manager has only when
your session imported it. When `show-environment` does not list it, add
`Environment=SSH_AUTH_SOCK=...` with the agent's socket to the service, run
`systemctl --user import-environment SSH_AUTH_SOCK` from a shell that has it, or name the agent
with `IdentityAgent` in `~/.ssh/config`, as the setup of the 1Password SSH agent does.

An agent that asks before it signs, as the 1Password one does while it is locked or before it
has approved the program asking, shows its prompt when the timer runs, whether or not you are
there to answer. Slipway keeps git and ssh from prompting, but the agent's own dialog is outside
ssh: the fetch waits until `networkTimeout` (60 seconds by default) ends it and every process it
started, and reports `failed (Timeout)`; a dismissed prompt reports `denied (AuthRequired)`. The
other projects fetch either way. `Environment=SLIPWAY_NETWORK_TIMEOUT=20` in the service shortens
that wait for the timer's runs alone.

### A daily routine

With the timer running, the first look of the day needs no network:

```sh
slipway get projects -A --field-selector status.state!=Clean
slipway diff -A
slipway sync -A
```

`get` lists the projects that need attention, with STATUS as of the timer's last fetch, whose
age FETCHED shows. `diff` says which of them sync will fast-forward, what blocks the others and
the git command that resolves each blocker, still without contacting a remote. `sync` fetches
once more, fast-forwards each clean branch that is behind and reports what it leaves alone with
the reason. To move only some projects, name them (`slipway sync hldr augur -n personal`) or
select them with `-l`. `slipway get projects -A --field-selector status.lastFetch=never` lists
the projects no fetch has reached, including those whose last fetch was denied or failed.
A fast-forward you did not want is undone with the `slipway rollout undo` command sync prints
under it, as [Rolling back](#rolling-back) describes.

## Output formats

`-o table` is the default. `-o wide` adds PATH, HEAD, LAST-COMMIT and DRIFT to projects and
DESCRIPTION to groups. `-o json` and `-o yaml` print the manifest plus a `status` section, as
one object when a single name is given and as a `kind: List` otherwise. `-o name` prints
`project/hldr` lines. `--no-headers` drops the header row and `--show-labels` appends a LABELS
column with `lang=rust` style pairs.

```console
$ slipway get projects -n personal -o wide
NAME    BRANCH   STATUS   FETCHED   AGE   PATH          HEAD      LAST-COMMIT   DRIFT
augur   main     Dirty    <never>   1s    ~/dev/augur   8f9cdbb   11h           NoUpstream
hldr    main     Clean    0s        1s    ~/dev/hldr    4c5d6e7   120m          <none>
```

AGE is the time since the resource was registered and LAST-COMMIT the age of the checked-out
commit, in kubectl's units (`3s`, `4m12s`, `11h`, `2y319d`). FETCHED is the time since the
repository was last fetched, by slipway or by git itself and from any of its worktrees. It reads
`<never>` when git answered and no fetch is on record, which includes a last fetch that failed,
and `<none>` when git could not read the repository at all (`Missing`, `NotARepo`, `Unsafe`,
`Unknown`), like every other cell that comes from git. BRANCH reads `(detached)` on a detached HEAD.
DRIFT lists the [drift](#drift) words.

`-o json` prints the same object as `-o yaml`. A project's `status` holds `branch`, `head`,
`upstream`, `ahead`, `behind`, the counts `staged`, `unstaged`, `untracked`, `conflicted` and
`stashes`, the STATUS word as `state`, `lastFetch`, the [drift](#drift) items as `drift` and the
checked-out commit as `lastCommit`:

```console
$ slipway get project augur -n personal -o yaml
kind: Project
metadata:
  name: augur
  group: personal
  labels:
    lang: bash
  creationTimestamp: '2026-09-29T07:15:35Z'
spec:
  path: "~/dev/augur"
status:
  branch: main
  head: 8f9cdbb
  staged: 0
  unstaged: 1
  untracked: 1
  conflicted: 0
  stashes: 0
  state: Dirty
  drift:
  - type: NoUpstream
    message: main tracks no upstream; sync fast-forwards only a tracking branch
    blocker: true
  lastCommit:
    hash: 8f9cdbbc5ff8982322347d8e6a76ea3ab8821b51
    author: Highlander
    email: contact@hvpaiva.dev
    date: '2026-09-28T20:15:35Z'
    subject: 'refactor: split history reader'
```

A field git could not answer is left out: augur has no `upstream`, `ahead`, `behind` or
`lastFetch`, and a project git could not read, such as a Missing one, keeps only `state` and
`drift`. A group's status holds `projects`, its project count.

## Status words

STATUS is one word per project, chosen in this order of precedence:

| STATUS | Meaning |
| --- | --- |
| `Missing` | The registered path is relative, or is not a directory on this machine. |
| `NotARepo` | The directory exists but no repository contains it. |
| `Unsafe` | git refused the repository because another user owns it (`safe.directory`); `describe`, `diff` and `fetch` print the git command that trusts it. |
| `Conflicted` | The working tree has unmerged paths. |
| `Detached` | HEAD points at a commit rather than a branch. |
| `Unborn` | The branch has no commits yet. |
| `Dirty` | Staged, modified or untracked files are present. |
| `Gone` | An upstream is configured but its remote-tracking ref is gone, as of the last `fetch --prune` (or a fetch with `fetch.prune` set). |
| `Diverged` | The branch is both ahead of and behind its upstream, as of the last fetch (FETCHED). |
| `Ahead` | Commits not yet pushed to the upstream, as of the last fetch (FETCHED). |
| `Behind` | Commits on the upstream not yet pulled, as of the last fetch (FETCHED). |
| `Clean` | Nothing to do. |
| `Unknown` | git could not answer: it is not installed, it did not finish within 10 seconds, or it failed for a reason slipway does not classify. Each distinct reason is printed once on stderr per run. |

`get`, `describe` and `diff` never contact a remote, so the words that compare a branch with its
upstream are as fresh as the last fetch. [Fetching](#fetching) refreshes them.

## Selectors

`-l EXPR` (`--selector`) filters by labels with kubectl's grammar. Equality:

```console
$ slipway get projects -A -l lang=rust
GROUP      NAME   BRANCH   STATUS   FETCHED   AGE
personal   hldr   main     Clean    0s        1s
```

Set-based:

```console
$ slipway get projects -A -l 'lang in (rust,bash)'
GROUP      NAME    BRANCH   STATUS   FETCHED   AGE
personal   augur   main     Dirty    <never>   1s
personal   hldr    main     Clean    0s        1s
```

`key!=value`, `key notin (a,b)`, `key` (exists) and `!key` (does not exist) work as well, and
comma-separated terms must all hold.

`--field-selector EXPR` filters `get` and `describe` on the fields of the object `-o json`
prints, with kubectl's field grammar: `path=value` (or `path==value`) and `path!=value`,
comma-separated, all of which must hold. Projects support `metadata.name`, `metadata.group`,
`spec.path`, `status.state`, `status.branch` and `status.lastFetch`; groups support
`metadata.name`.

```console
$ slipway get projects -A --field-selector status.state!=Clean
GROUP      NAME    BRANCH   STATUS     FETCHED   AGE
default    notes   main     Diverged   0s        1s
personal   augur   main     Dirty      <never>   1s
```

`status.lastFetch=never` selects the projects no fetch has reached. The `--field-selector` help
and slipway-get(1) give the matching rules. Neither kind of selector, nor `-A`, can be combined
with explicit names.

## Manifests

Every registration is a manifest. `slipway get project hldr -n personal -o yaml` prints it
followed by `status`; without the status, a Project and a Group look like this:

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
characters) and labels follow the Kubernetes rules. `metadata.group` defaults to the current
group and `creationTimestamp` is set on creation; written by hand, it must be a quoted string.
Unknown fields are errors.

A project's spec says where its repository is and declares the state it is expected to be in.
Only `spec.path` is required, and a field at its default is not written:

| Field | Meaning | Default |
| --- | --- | --- |
| `spec.path` | The directory of the repository: an absolute path, or one starting with `~/`, which is expanded against `HOME` when used so that the manifest means the same on every machine. A relative path is reported as `Missing`. Must not be empty. | required |
| `spec.description` | What the project is, in free text. | none |
| `spec.remote` | The URL the `origin` remote is expected to have; `diff` reports another one as `Remote` drift, and no command changes a remote. A password, or any user name over http and https, where it often carries a token, is refused; use a credential helper. Must be `scheme://host/path` with scheme `ssh`, `https`, `http`, `git` or `file`, or `[user@]host:path`, where the host is letters, digits, dots and dashes starting with a letter or digit; at most 2048 characters, without whitespace or control characters. | none |
| `spec.branch` | The branch expected to be checked out; `diff` reports another one as `Branch` drift, and no command switches branches. Must be letters, digits, ".", "_", "/" and "-", starting with a letter or digit, at most 255 characters, with no "..", no "//", no component that starts with "." or ends with ".lock", no trailing "/" or ".", and not `HEAD`. | none |
| `spec.revision` | The commit the project is held at, named in full because an abbreviation can become ambiguous. `sync` fast-forwards the branch up to it instead of the upstream, never past it and never back to it. `rollout undo` writes it and `rollout unpin` removes it. Must be a full object name, 40 or 64 lowercase hexadecimal characters. | none |
| `spec.syncPolicy` | What `sync` may do to the repository: `FastForward` lets it fast-forward the checked-out branch, and `FetchOnly` lets it fetch only. Must be `FastForward` or `FetchOnly`. | `FastForward` |
| `spec.paused` | When `true`, `fetch` and `sync` leave the project alone: they report it as `paused` and run no git command there. `rollout pause` sets it and `rollout resume` removes it. | `false` |

A `~` path is stored as written. `create` resolves any other relative `--path`, `.` included,
against the current directory and stores it absolute. The shell expands an unquoted `~` before
slipway sees it, so quote it, as the examples here do, to keep the manifest portable.

`fetch` and `sync` leave a project with `spec.paused: true` alone, and `sync` follows
`spec.syncPolicy` and `spec.revision`. STATUS does not take any of the fields into account; the
repository is compared with them as [drift](#drift). The fields are checked whenever a manifest
is read, and a value that breaks its rule is refused with that rule, so nothing that could reach
git as an option or carry a control character is accepted. A file in the registry that cannot
be read is reported with a `warning:` line and left out of listings.

`slipway apply -f FILE` reads every YAML document in the file, `-f DIR` reads every `*.yaml`
and `*.yml` file in the directory sorted by name (without descending), and `-f -` reads stdin.
`-f` may be repeated. A document of kind `List` stands for each manifest under its `items`, in
order, and one that fails is named by its position (`FILE:3`). Each document prints
`project/hldr created`, `configured` or `unchanged`; problems are collected and printed as
`error: FILE[:N]: ...` after the successes, with exit status 1.

### Drift

Drift is where a project's repository differs from its manifest, and what keeps sync from
fast-forwarding it. `-o wide` lists the words in the DRIFT column, `-o json` and `-o yaml` list
the items in `status.drift` (each with `type`, `message` and `blocker`), and `describe` ends
with a Drift block of one line per item. Nothing is fetched: the repository is read as it is on
disk, so Behind is as of the last fetch (FETCHED), and `slipway fetch` refreshes it.

| Drift | Reported when |
| --- | --- |
| `Missing` | The registered path is relative or is not a directory. For a path that is not a directory, a project with `spec.remote` shows the `git clone` command that recreates it. |
| `Remote` | origin is absent or differs from `spec.remote`. Sync never changes a remote. |
| `Branch` | HEAD is detached or on another branch than `spec.branch`. Sync never switches branches. |
| `Revision` | HEAD is not the commit `spec.revision` pins. The pin replaces the upstream, so a pinned project is never Behind; under `FastForward` sync will fast-forward a branch behind the pin to it unless a blocker stops it, and never moves a branch back. |
| `Behind` | The checked-out branch is behind its upstream. Under `FastForward` sync will fast-forward it unless a blocker stops it; under `FetchOnly`, or while `spec.paused` is true, it is only reported. |

A blocker comes after the drift and says why the checked-out branch cannot be fast-forwarded,
onto its upstream or, for a project pinned by `spec.revision`, onto the pin. The first three mean
git could not read the repository and apply to every project; the others apply only under
`FastForward` to a project that is not paused, and `RevisionNotFound`, `PastRevision` and
`OffUpstream` only to a pinned one. Behind means behind the upstream or, when pinned, behind the
pin:

| Blocker | Meaning |
| --- | --- |
| `NotARepo` | The directory exists but holds no repository. |
| `Unsafe` | git refused the repository because another user owns it (`safe.directory`); the git command that trusts it follows. |
| `Unknown` | git could not answer; the reason is also printed once on stderr. |
| `Detached` | HEAD points at a commit rather than a branch. |
| `Unborn` | The branch has no commits yet. |
| `Gone` | The upstream is configured but its ref no longer exists. |
| `NoUpstream` | The branch tracks no upstream. |
| `RevisionNotFound` | The repository has no commit by the name `spec.revision` pins. |
| `PastRevision` | HEAD is past the pinned commit or on another line of history, so reaching the pin would move the branch back. |
| `OffUpstream` | The upstream does not hold the pinned commit, which may be on another branch or a fork; sync moves a branch only along its upstream. |
| `Conflicted` | The branch is behind and the working tree has unmerged paths. |
| `Dirty` | The branch is behind and has staged or unstaged changes; untracked files do not block. |
| `Diverged` | The branch is behind and has commits of its own. |
| `InProgress` | The branch would be fast-forwarded, but a merge, rebase, cherry-pick, revert, bisect or `git am` is in progress. |

## Discovering resources

`slipway api-resources` lists the resource types, as `kubectl api-resources` lists the ones a
cluster serves:

```console
$ slipway api-resources
NAME       SHORTNAMES   KIND      GROUPED
groups     <none>       Group     false
projects   proj         Project   true

$ slipway api-resources -o wide
NAME       SHORTNAMES   KIND      GROUPED   VERBS
groups     <none>       Group     false     apply,create,delete,describe,edit,get,label
projects   proj         Project   true      apply,create,delete,describe,diff,edit,fetch,get,label,rollout,sync
```

A command accepts a type by its NAME, its singular or one of its SHORTNAMES, and KIND is what a
manifest of the type declares in `kind`. GROUPED plays the part of kubectl's NAMESPACED: it says
whether the resources of a type live in a group, so that `-n` and `-A` scope them. VERBS lists
the commands that act on the type, and `-o name` prints the names alone.

## Configuration

Settings are resolved in this order: command-line flags, then `SLIPWAY_*` environment
variables, then the config file, then the built-in defaults. The file lives at
`$XDG_CONFIG_HOME/slipway/config.yaml` (`~/.config/slipway/config.yaml`) unless `--config PATH`
or `SLIPWAY_CONFIG` names another one. The default file is optional, and so is every key in it;
a file named by `--config` or `SLIPWAY_CONFIG` must exist.

```yaml
# ~/.config/slipway/config.yaml
color: auto              # auto, always or never
theme: light             # dark or light
editor: code --wait
group: personal          # used when -n is not given
networkTimeout: 60       # seconds before a git network command is killed, from 1 to 86400
parallel: 4              # git network commands at once, from 1 to 16
protocols: [ssh, https]  # transports git may use; add file for local mirrors
```

The defaults are `color: auto`, `theme: dark`, `group: default`, `networkTimeout: 60`,
`parallel: 4` and `protocols: [ssh, https]`; `editor` has none, so `edit` falls back to
`VISUAL`, `EDITOR` and `vi`. `slipway config view` prints the values in effect with the file
path as a comment on the first line, and `slipway config path` prints the path alone. An unknown
key or a wrong value is an error naming the file. `protocols` refuses `ext` and `fd` even when
listed: `ext` runs a command named in the URL, and `fd` reads from file descriptors.

| Variable | Effect |
| --- | --- |
| `SLIPWAY_CONFIG` | Path of the configuration file; `--config` outranks it. |
| `SLIPWAY_DATA_HOME` | Directory holding the registry. |
| `SLIPWAY_COLOR` | `auto`, `always` or `never`; `--color` outranks it. |
| `SLIPWAY_THEME` | `dark` or `light`. |
| `SLIPWAY_EDITOR` | Editor for `edit`; outranks the config key, `VISUAL` and `EDITOR`. |
| `SLIPWAY_GROUP` | Group used when `-n` is not given. |
| `SLIPWAY_NETWORK_TIMEOUT` | Seconds a git network command may run before it is killed, from 1 to 86400. |
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
colors, green for `Clean`, yellow for the states that ask for a git action (`Detached` through
`Behind` in the [STATUS table](#status-words)), red for `Missing`, `NotARepo`, `Unsafe` and
`Conflicted`, and grey for `Unknown`.

## Shell completion

`slipway completion SHELL` prints the script; the header of each script says where it goes.

```sh
# bash: load it in the current session, or add the line to ~/.bashrc
eval "$(slipway completion bash)"
# bash: install it for bash-completion to load on demand
mkdir -p "${XDG_DATA_HOME:-$HOME/.local/share}/bash-completion/completions"
slipway completion bash > "${XDG_DATA_HOME:-$HOME/.local/share}/bash-completion/completions/slipway"

# zsh: put _slipway in a directory on your fpath (fpath+=~/.zfunc before compinit), or source it directly
mkdir -p ~/.zfunc
slipway completion zsh > ~/.zfunc/_slipway
source <(slipway completion zsh)

# fish
mkdir -p ~/.config/fish/completions
slipway completion fish > ~/.config/fish/completions/slipway.fish
```

Completion covers commands, flags, flag values (`-o js<TAB>` gives `json`), resource types and
the names of your projects and groups, asked from the program itself each time you press TAB.

## Manual pages

The pages are installed with slipway. `slipway man` opens `slipway(1)` and `slipway man get`
opens `slipway-get(1)` with `man(1)`, colored like the help page when color is on; if any of
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

`slipway diff` also exits with 3 when a project differs from its manifest. The man pages of
`diff`, `sync` and `rollout undo` list their statuses.

## Development

```sh
git clone https://github.com/hvpaiva/slipway.git
cd slipway
bin/setup
bundle exec rake         # tests and RuboCop
bundle exec rake check   # what CI runs
```

`bin/setup` installs the development dependencies and reports the tools it found.
`bin/sandbox` opens a shell whose `slipway` is the checkout, against an empty registry and
configuration in a temporary directory, to [try a change by
hand](CONTRIBUTING.md#trying-a-change-by-hand).

## Other documents

- [CONTRIBUTING.md](CONTRIBUTING.md) for the rake tasks, the conventions, the generated files and the release process.
- [ARCHITECTURE.md](ARCHITECTURE.md) for a map of the code.
- [CHANGELOG.md](CHANGELOG.md) for what changed in each version.
- [SECURITY.md](SECURITY.md) for what slipway promises about the repositories it touches and how to report a vulnerability.
- [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) for the rules of the community.

## License

MIT. See [LICENSE.txt](LICENSE.txt).
