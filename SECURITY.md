# Security

## Supported versions

Slipway is pre-1.0. Only the latest 0.x release published on RubyGems receives security fixes;
older releases are not patched. Run `slipway version` to see what you have.

| Version | Supported |
| --- | --- |
| Latest 0.x | Yes |
| Anything older | No |

## Reporting a vulnerability

Please do not open a public issue for a security problem. Report it privately through GitHub's
private vulnerability reporting on the repository:

https://github.com/hvpaiva/slipway/security/advisories/new

If that is not an option for you, email contact@hvpaiva.dev with "slipway security" in the
subject.

Include what you can of the following:

- The version (`slipway version` output) and the operating system.
- What the problem is and what an attacker gains from it.
- Steps or a manifest, config file or command line that reproduces it.
- Whether you have already shared it anywhere else.

Slipway reads files under the user's own home directory, runs `git` in the directories the user
registered and, in `fetch` and `sync`, contacts their remotes. The areas worth attention are: a
manifest or config file crafted by someone else, applied with `slipway apply -f` or carried in a
registry copied between machines; the way `git` is invoked on a registered path; what a remote
or a repository can make slipway print; the fast-forward `sync` performs and the moves
`rollout undo` makes; and the temporary files `edit` writes. A way to break one of the
[safety promises](#safety-promises) is a vulnerability.

## What happens next

You will get an acknowledgment, usually within a few days; this is a one-person project, so
there is no guaranteed response time. I will confirm the problem, work out a fix and agree on
a disclosure date with you. Fixes ship as a new version on RubyGems, and the changelog entry for
that version references the advisory. If the vulnerable version has to be pulled, it is yanked
from RubyGems after the fixed one is available. Credit goes to the reporter unless you prefer
otherwise. How a fix release and a yank are carried out is described in
[Hotfixes and yanking](CONTRIBUTING.md#hotfixes-and-yanking).

## Safety promises

Slipway runs git in the repositories that hold your work, contacts their remotes and prints what
they answer, and keeps these promises while doing so.

### What slipway trusts

Policy comes from you alone: the command line, the `SLIPWAY_*` variables and the configuration
file decide which transports git may use, how long a network command may run and how many run at
once. Everything else is data.

- A manifest may come from another machine or another person, through `apply -f` or a registry
  copied between machines. Nothing in it is executed, and no field in it can widen a setting of
  the configuration file or the command line: `spec.paused` can only keep `fetch` and `sync`
  away, `spec.syncPolicy` can only keep `sync` from moving a branch, and `spec.revision` can only
  hold a branch back.
- Text that git or a remote prints, such as ref names, commit subjects, author names and error
  messages, is only ever displayed, and only as described under [Output](#output).

Registering a path trusts the repository at it the way running `git` there does: git reads that
repository's configuration along with yours, and runs the hooks and programs they name. Git's
ownership check still applies: a repository another user owns is reported as `Unsafe` and left
alone, and slipway prints git's command to trust it instead of adding it to `safe.directory`.

### Manifests

- Every field that could reach git or a git command slipway prints is checked whenever a
  manifest is read, by `apply`, `create`, `edit` or any verb that lists the registry, against a
  closed rule: `spec.remote` is a URL of a listed form without credentials, `spec.branch` a
  restricted branch name and `spec.revision` a full object name of 40 or 64 hexadecimal
  characters. None of them can start with `-` or hold a control character. A manifest that
  breaks a rule is refused, and one already in the registry is reported and left out.
- Git receives the repository's directory as an absolute path, and the only other manifest value
  that reaches a git command line is `spec.revision`, as the full object name its rule allows.
  `spec.remote` never does.
- The git commands `diff` and `sync` suggest, such as `git -C ~/dev/notes remote set-url origin
  URL`, are printed for you to run and never run by slipway. Every word in them that came from a
  manifest or from git reaches the shell as that one word.

### Reading

- `get`, `describe`, `diff` and `rollout history` read repositories as they are on disk. They
  never write to a repository and never contact a remote: git runs with `GIT_OPTIONAL_LOCKS=0`,
  so reading a status does not even refresh the index, and asking whether a partial clone holds
  a pinned commit never fetches it.
- Only `fetch` and `sync` contact remotes, and not with `--dry-run=client`; a move of
  `rollout undo` in a partial clone may fetch the objects it writes, as a fast-forward may. Only
  `create`, `apply`, `delete`, `edit`, `label` and the `rollout` verbs other than `history`
  write the registry.

### Fetching

- `fetch` runs `git fetch` without a remote argument, so git picks the remote a `git fetch` typed
  in the repository would. Git updates the refs the remote's fetch refspecs name
  (remote-tracking refs by default), tags and `FETCH_HEAD`, never the checked-out branch or the
  working tree.
- Refs are pruned only when `--prune` asks for it or your own `fetch.prune` or
  `remote.<name>.prune` setting does, and then only the ones your fetch configuration names:
  remote-tracking refs by default.
- A branch that tracks another local branch is skipped as `LocalUpstream` instead of fetched from
  the repository itself.
- Within one run, two commands that write into one repository, such as the fetches of a linked
  worktree and of its main one, never run at once.

### Writes to a working tree

`sync` and `rollout undo` are the only verbs that change a working tree. `sync` has one way to
do it: `git merge --ff-only --no-autostash --no-overwrite-ignore` of the checked-out branch, onto
its upstream or up to the commit `spec.revision` pins when the upstream holds that commit. It
runs only when all of these hold, and the repository is read again right before git merges:

- `spec.syncPolicy` is `FastForward` and `spec.paused` is not true.
- HEAD is on a branch that has commits.
- The branch tracks an upstream that still exists.
- Nothing is staged, unstaged or conflicted.
- No merge, rebase, cherry-pick, revert, bisect or `git am` is in progress, and no lock on the
  branch is held.
- After the fetch, the branch has no commits of its own and is behind.

`--ff-only` is git's own last check. When git refuses, because an untracked or ignored file is in
the way, a local change `git status` does not show would be lost, another process holds
`index.lock` or the branch gained a commit since the check, the project is reported as skipped,
and the branch, the index and the working tree stay as they were. A fast-forward stopped at the
deadline or by Ctrl-C also leaves the branch and the index where they were, but the files git had
already written stay in the working tree and show as changes; at the deadline the project is
reported as `failed (Timeout)` with the command that lists them. Fast-forwards run one at a
time, and each is recorded as `slipway sync: Fast-forward` in the branch's reflog when git keeps
one (`core.logAllRefUpdates`, on by default), so `git reflog show BRANCH` lists the moves slipway
made until git expires them.

`rollout undo` moves the checked-out branch only to a revision slipway recorded: a commit a
`slipway sync` or `slipway rollout undo` entry of the branch's reflog moved it to, or the commit
it stood at before such a move. A move back runs
`git reset --keep --quiet --no-recurse-submodules`, the only form of reset slipway runs, and only
when all of these hold:

- HEAD is on a branch that has commits and tracks an upstream that still exists.
- Nothing is staged or conflicted, and no merge, rebase, cherry-pick, revert, bisect or `git am`
  is in progress.
- The revision is on the branch's history, and the upstream holds every commit the move removes,
  so no commit that exists only in this repository is dropped.
- No untracked or ignored file is in the way of a file the move adds: `reset --keep` would
  replace an ignored one without a word, so slipway refuses first.

`reset --keep` itself keeps an unstaged change to a file the move leaves alone and refuses one to
a file it rewrites. A move forward, which undoes an undo, is the fast-forward above, run only on a
tree without staged or unstaged changes and to a revision the upstream holds. Either move is
recorded as `slipway rollout undo` in the branch's reflog, a refusal leaves the branch, the index
and the working tree as they were, a move stopped partway keeps the files git had written as a
fast-forward does, and `spec.revision` is written only after git moved the branch.

### What slipway never does

- It never runs `pull`, `rebase`, `checkout`, `switch`, `stash`, `clean`, `gc` or `push`, and
  runs `reset` only as the `reset --keep` of a `rollout undo` move back, described above. It
  never passes `--autostash`, `--hard` or `--force` to git.
- It never switches a branch or changes a remote. A branch or an origin that differs from the
  manifest is reported with the command that would change it.
- It never deletes a lock file, a branch, a tag or a remote itself, and the only refs a git
  command it runs removes are the ones pruning removes. A lock another git process holds, or left
  behind, is reported as `Busy` and kept.
- It never trusts, unlocks or forces a repository it cannot use: `NotARepo`, `Unsafe`,
  `Unknown`, an operation in progress and `Busy` are reported and skipped.
- It never fetches or updates submodules.

### How git runs

- Every git command starts from one place in the code, in a process group of its own, with
  standard input closed and a deadline: 10 seconds for a local command, `networkTimeout` (60
  seconds by default) for a fetch or a move of the branch. At the deadline, or on Ctrl-C, the whole
  group is stopped, which ends git and the helpers it started there, such as ssh.
- Each runs with `LC_ALL=C`, `GIT_TERMINAL_PROMPT=0` and `GIT_OPTIONAL_LOCKS=0`; with
  `GIT_DIR`, `GIT_WORK_TREE`, `GIT_INDEX_FILE`, `GIT_NAMESPACE`, `GIT_OBJECT_DIRECTORY` and
  `GIT_ALTERNATE_OBJECT_DIRECTORIES` unset, so an inherited variable cannot point git at another
  repository; and with `GIT_CEILING_DIRECTORIES` set, so git never answers for a repository above
  the registered directory.
- A fetch or a move of the branch, which may fetch objects into a partial clone, also runs with
  `GIT_ASKPASS` and `SSH_ASKPASS` pointing at `false` and `SSH_ASKPASS_REQUIRE=force`, so a
  question about a password, a passphrase or a host key fails at once instead of waiting for an
  answer (ssh honors `SSH_ASKPASS_REQUIRE` from OpenSSH 8.4 on; an older ssh may still ask on the
  terminal); with `GIT_ALLOW_PROTOCOL` built from `protocols` (ssh and https by default), so git
  itself refuses any other transport; and with `gc.auto=0`, `maintenance.auto=false` and
  `transfer.bundleURI=false`. `protocols` refuses `ext` and `fd` even when listed.
- At most `parallel` fetches run at once, 4 by default and 16 at most.
- Your configuration is used, never overridden: slipway sets no `GIT_SSH_COMMAND`,
  `core.sshCommand`, `credential.helper`, `core.hooksPath`, `safe.directory` or include
  directive, so your ssh configuration, agent, credential helpers and hooks work as they do in a
  terminal.

### Output

- Text from git or a remote is printed with its control characters made visible: C0 characters
  and DEL in caret notation (ESC as `^[`), C1 characters and the bidirectional embedding,
  override and isolate controls as U+FFFD. This holds in tables, `describe`, the `status` of
  json and yaml output, result details, warnings and `error:` lines, so that text can neither
  move the cursor, color a line nor reorder one.
- A git failure is reported by a single line of git's stderr, cut to 200 characters. Beyond the
  refs a fetch moved, what git and your hooks print when a command succeeds is not shown.
- Credentials in a URL are masked as `***` wherever slipway prints one: the whole user part over
  http and https and the schemes that carry them, such as `git+https`, and the password
  elsewhere. The mask is applied before the cut, so a password cannot survive in a truncated URL.
- Slipway keeps no log file.

### Failures

- A git failure in one project never stops the others. `fetch` and `sync` print at least one line
  for every project, in the order listed, and exit with status 1 when any project was denied or
  failed, once every line has printed. A skipped project never changes the exit status.
- Running `sync` again does only what is left: a branch it fast-forwarded reads `unchanged` the
  next time.

### Tests

No test contacts the network. Tests that need a remote use local repositories over the file
transport, which only the test's own configuration allows, or a stand-in for the git executable.
