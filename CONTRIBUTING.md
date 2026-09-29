# Contributing

Thanks for taking the time. This page covers the workflow; [ARCHITECTURE.md](ARCHITECTURE.md)
explains where things live and how to add a verb, an option, a completer or a theme role.

## Setup

You need Ruby 3.4 or newer (the repository pins 4.0.7 in `mise.toml`) and git 2.35 or newer.
The optional checks use `shellcheck`, `groff`, `zsh`, `fish`, `docker`, `gh` and `typos`.

```sh
git clone https://github.com/hvpaiva/slipway.git
cd slipway
bin/setup
bundle exec ruby -Ilib exe/slipway --help
```

`bin/setup` runs `bundle install` and ends with a report: the Ruby it found against
`mise.toml`, the git version (older than 2.35 is a hard failure, with the reason), and one line
per optional tool saying which task skips or fails without it. `bin/console` opens IRB with the
gem loaded.

## Tests and lint

```sh
bundle exec rake         # the fast loop: tests and RuboCop
bundle exec rake check   # what CI runs
```

`rake check` runs, in this order, RuboCop, ShellCheck over `bin/setup` and the bash completion
script, `groff -ww` over the man pages, the unit and golden tests under SimpleCov with the
coverage minimums, the integration tests, the generated-files comparison, the package smoke
test (build, install into a temporary `GEM_HOME`, run the installed executable) and, last,
bundler-audit. Set `CHECK_OFFLINE=1` to skip the audit when you have no network; the task says
so when it does. CI runs the same tasks. What `rake check` leaves out is what one machine
cannot cover: the Ruby 3.4 and macOS entries of the test matrix, and the `completions` job,
which fails when zsh or fish is missing (run it with `bundle exec rake test:shells`, see
[Testing completions](#testing-completions)). CI also lints the commits of every pull request
([Commits](#commits)) and runs the spelling, workflow and link checks listed under
[Checked by tools](#checked-by-tools).

The individual tasks (`rake test`, `test:cov`, `rubocop`, `lint:man`, `lint:shell`, `audit`
and the rest) are listed in the [README](README.md#development). Everything runs against
temporary directories and repositories created for the test, never against your own registry.

## Conventions

### Checked by tools

Each of these fails `rake check` or CI when it is broken.

- RuboCop passes with the configuration in `.rubocop.yml`: the defaults with `NewCops:
  enable`, the minitest, performance and rake plugins, single quotes, and the `Metrics` limits
  set there. Inline `rubocop:disable` comments are an offense themselves; if a method outgrows
  the limits, split it. Exceptions to a RuboCop rule live in `.rubocop.yml`, never inline.
- Every Ruby file starts with `# frozen_string_literal: true`. Requires inside the gem use
  `require_relative`; a `require 'slipway/...'` line fails `test/unit/conventions_test.rb`.
- Everything under `lib/`, `exe/`, `bin/`, `rakelib/` and the golden fixtures is ASCII.
- No new runtime dependencies: the gemspec's `runtime_dependencies` must stay empty, and the
  gem ships only `lib/`, `exe/`, `man/`, `README.md`, `CHANGELOG.md` and `LICENSE.txt`.
- Coverage stays above the line and branch minimums in the Rakefile, overall and per file.
- Dependencies point one way: the command layer under `cli/` and the domain files never
  require commands, views, the runtime, the inspector or the pool, and `cli/` requires one file
  outside itself (`cli/errors.rb` requires `error.rb`). [ARCHITECTURE.md](ARCHITECTURE.md#layers)
  has the full rule.
- `Git::Runner` is the only place that spawns git, `yaml.rb` is the only YAML writer, and
  nothing under `lib/` writes to stdout or stderr except `cli/context.rb`.
- The man page ENVIRONMENT section and the README variable table list every variable the code
  reads except `HOME` and `PATH`, the README tables for STATUS words, exit statuses and rake
  tasks match the code, and the README configuration example sets every config key and no
  other.
- `CHANGELOG.md` keeps the Keep a Changelog shape: `## [Unreleased]` first, one heading per
  release, dated `YYYY-MM-DD` and ordered newest first by version and date, and a link
  reference for every heading and a heading for every link reference.
- Spelling, with `typos` over source and docs; the workflows, with `zizmor`; the links and
  anchors in the guides, with `lychee`.

### Reviewed by people

No tool checks these; a reviewer does.

- Comments explain why the code is the way it is, never what it does. A comment that restates
  the code is removed in review.
- Every change ships with tests. A bug fix starts with a test that fails; a new option or verb
  gets unit tests in `test/unit/commands` and, when it prints something, an exact-output
  assertion. The coverage minimums are the mechanical floor; review judges whether the tests
  say anything.
- User-visible text follows kubectl's wording: `project/hldr created`, `No resources found in
  work group.`, `error: projects "hldr" not found`. When kubectl has a phrase for the situation,
  use it. Everything is in English. The golden fixtures freeze that wording, so every change to
  a fixture is reviewed as an interface change.
- One change per commit and one subject per pull request; what counts as one change is
  judgment.

## Generated files

Two kinds of generated text are committed: the man pages under `man/man1`, rendered from the
command definitions, and the golden fixtures. Those under `test/fixtures/golden` freeze the
text of every help page and of the three completion scripts; the two under `test/fixtures/man`
freeze the roff the man page builder writes for the test registry. After changing a command, an
option, a description or an example, run

```sh
bundle exec rake generate
```

review the diff it prints at the end, and commit the pages and fixtures with the change. The
task renders the pages, lints them with groff, rewrites the golden fixtures from the current
output and removes fixtures that no longer belong to a command. Forgetting it is caught: a
stale fixture fails its test with a diff, a new command without its fixture fails
`test_every_fixture_belongs_to_a_command` in `test/golden/help_test.rb`, a missing page fails
`test_man1_holds_exactly_the_rendered_pages` in `test/golden/manpage_test.rb` and a stale one
fails that page's `_is_fresh` test, and the CI `generated` job fails when the committed pages
differ from what `rake generate:check` renders.

The page date comes from the newest `## [x.y.z] - YYYY-MM-DD` heading in `CHANGELOG.md` and is
empty while the changelog has no release heading, so a plain change does not touch the date.
The completion scripts themselves are rendered at run time and never committed; the fixtures
only freeze their text. `rake lint:shell` runs ShellCheck over the bash one as
`slipway completion bash` prints it.

## Testing completions

The completion scripts are tested in real shells by `test/unit/cli/completion_scripts_test.rb`.
Locally, bash is always exercised (with and without `bash-completion` when
`/usr/share/bash-completion/bash_completion` exists); zsh and fish skip when they are not
installed. To try a script by hand:

```sh
eval "$(bundle exec ruby -Ilib exe/slipway completion bash)"
slipway get <TAB>
```

To be sure nothing was skipped, run

```sh
bundle exec rake test:shells
```

With zsh and fish on `PATH`, it runs that one test file with `SLIPWAY_REQUIRE_SHELLS=1`, which
is exactly what the CI `completions` job does. Without them, it runs the same file with docker,
as your user, in an image built from `ruby:4.0` with zsh, fish, bash-completion and ShellCheck
added; the gems live on a named volume so the second run is fast. With neither the shells nor
docker, it stops and tells you what to install.

## Commits

- Conventional Commits in English and the imperative: `feat: add the label verb`,
  `fix: prune the group directory after the last delete`, `docs:`, `test:`, `refactor:`,
  `chore:`, `ci:`. An optional scope is allowed, as in `chore(deps): bump rubocop`. The subject
  git writes for a revert, `Revert "<subject>"` (or `Reapply "<subject>"` for a revert of a
  revert), is accepted when the quoted subject follows these rules.
- One change per commit, with its tests and generated files. No `WIP`, `fixup!`, `amend!` or
  `squash!` commits in a pull request, and no summary that starts with `wip`.
- Commits are signed by their author (`git commit -S`, with an SSH or GPG key registered on
  GitHub as a signing key; GitHub's guide covers [signing commits with an SSH
  key](https://docs.github.com/en/authentication/managing-commit-signature-verification/telling-git-about-your-signing-key#telling-git-about-your-ssh-key)).
- Attribution trailers for tools (`Co-Authored-By` lines with an assistant's or a GitHub app's
  address, `Generated-by`, `Generated-with`, `Assisted-by` and the like) are not accepted, in
  commits or in pull request descriptions. Human co-authors are welcome.

The `commits` job runs `bin/lint-commits` on every pull request over the commits it adds, its
title and its body: the subject format, the WIP and fixup rule, and the attribution trailers
are all checked there. Merge commits are included but checked for attribution trailers only,
because git writes their subject. The `main` ruleset on GitHub requires the rest: signed commits, a pull
request for everyone including the maintainer, green required checks, and merge commits as the
only merge method. Squash and rebase are disabled so your atomic commits land as you signed
them; GitHub signs the merge commit. To check a branch before pushing it, run
`bin/lint-commits origin/main..HEAD`.

## Pull requests

- Open an issue first for anything larger than a fix, so the shape can be agreed before the
  code exists.
- Keep the pull request to one subject. Describe what changed and how you tested it; the
  template asks for both.
- `bundle exec rake check` is expected green before you open it; the required checks are the
  same tasks.
- User-visible changes get a line under `## [Unreleased]` in `CHANGELOG.md`. The `commits` job
  fails a pull request that touches `lib/`, `exe/` or `man/` without touching the changelog,
  unless the pull request carries the `skip-changelog` label: that is the explicit exception,
  for refactors, internal fixes and dependency updates.
- Expect review comments on wording as much as on code; the help texts and messages are part
  of the interface.

## Releasing

Releases are cut by a maintainer with `bin/release`, from `main` unless `--branch` says
otherwise. `rake release` is the publish step and refuses to run outside GitHub Actions, as do
Bundler's `rake release:source_control_push` and `rake release:rubygem_push` run on their own,
so the tag is the only thing that publishes.

```sh
bin/release X.Y.Z            # validate, prepare and open the release pull request
bin/release X.Y.Z --push     # the same, then merge, tag and watch the Release workflow
bin/release X.Y.Z --dry-run  # validate and show the diff without writing anything
```

`bin/release X.Y.Z` validates before touching anything: the version parses with `Gem::Version`,
has no prerelease suffix and is greater than `Slipway::VERSION`, or equal to it while
`CHANGELOG.md` has no heading for it (`version.rb` holds the version under development, so the
first release is `bin/release 0.1.0`); the tree is clean, on `main` and equal to `origin/main`
after `git fetch origin --tags`; the tag `vX.Y.Z` exists neither locally nor on origin;
`## [Unreleased]` has at least one entry; and the repository is set up (the `release`
environment with its `v*` policy and the `main` ruleset exist), otherwise it stops and names
`bundle exec rake github:setup` as the fix. When `CHANGELOG.md` already has the heading but
origin has no tag, a release that stopped after the merge, it names what is left instead of
asking for a greater version: `git push origin vX.Y.Z` when the tag exists locally, or, when the
release pull request is merged and the tag exists nowhere, `git tag -s vX.Y.Z -m vX.Y.Z` on the
merge commit that `gh pr list` reports (fetched first, so the command works as printed),
followed by the push. It then creates the branch `release/vX.Y.Z`, writes
`lib/slipway/version.rb`, rewrites `CHANGELOG.md` (today's date in UTC on the new heading, an
empty `## [Unreleased]` above it, the `[Unreleased]` and `[X.Y.Z]` link references, older
references kept), runs `bundle exec rake generate` so the man pages carry the date, runs
`bundle exec rake check`, commits `chore: release vX.Y.Z` with a signature (the two files, the
regenerated pages and fixtures, and `Gemfile.lock`, which records the new version), pushes the
branch, opens the pull request with `gh pr create` and stops, printing what comes next. A
failure in `rake check` leaves the edits in place for you to inspect.

With `--push` it continues once the pull request exists: waits for the checks with
`gh pr checks --watch --fail-fast`, merges with `gh pr merge --merge --delete-branch`, fetches
`main`, creates the signed annotated tag with `git tag -s vX.Y.Z -m vX.Y.Z` on the merge commit,
pushes the tag and follows the Release workflow with `gh run watch`. A failed tag names the
`git tag -s` command for the merge commit and the push; a failed tag push names
`git push origin vX.Y.Z`; a failed Release run says to rerun the failed jobs, or only
`github-release` once the gem is on rubygems.org. Without `--push`, review the pull request,
merge it, and tag the merge commit by hand:

```sh
git switch main
git pull --ff-only origin main
git tag -s vX.Y.Z -m vX.Y.Z
git push origin vX.Y.Z
```

`--dry-run` runs the validations and prints the diff of `version.rb` and `CHANGELOG.md`; it
writes nothing, commits nothing and calls no GitHub write API. `--branch NAME` releases from
`NAME` instead of `main`, for hotfixes.

The tag starts the Release workflow (`.github/workflows/release.yml`). It runs the whole CI
workflow on the tagged commit, then checks that the commit is on `main` or on a `hotfix/*`
branch, runs `rake release:verify` (the tag equals `v` + `Slipway::VERSION`, the changelog has
the dated heading and its link reference, `## [Unreleased]` is present), builds the gem and
publishes it to RubyGems through trusted publishing (no API key is stored anywhere; the job gets
a short-lived OIDC token in the `release` environment, with `id-token: write` and read-only
contents). `rubygems/release-gem` runs with `await-release` and `attestations` off, because
both download and run unpinned gems while the push credential is on disk. A separate
`github-release` job then rebuilds the gem from the tag (RubyGems builds reproducibly, so it is
the file that was pushed) and creates the GitHub release with the changelog section as its
notes and the gem attached. rubygems.org refuses a version it already has, so when only that
job fails, rerun it alone. A manual run from a branch has no tag and checks `CHANGELOG.md` as
`bin/release` would cut it, so the dry run passes before the first release.

### One-time setup of the repository and the trusted publisher

```sh
bundle exec rake github:setup
```

The task configures the repository through `gh api` and is safe to run again; it prints what it
created and what already existed. It makes merge commits the only merge method (squash and
rebase disabled), titles each merge commit after its pull request with an empty body, and
deletes the branch once merged; creates the `release` environment with a deployment policy
limited to `v*` tags, the `main` ruleset (pull request required with no mandatory approvals, the required status
checks, signed commits, no force pushes, no deletions), the `tags` ruleset that restricts
creating, updating and deleting `v*` tags to the repository admin, and the `skip-changelog`
label; and turns on vulnerability alerts, automated security fixes and immutable releases (a
published release can never have its tag moved or its assets replaced, and GitHub attests it).
It ends by printing the RubyGems publisher table below and the 12-hour reminder.

The RubyGems side is a click in the web UI, behind MFA, so it stays manual. On rubygems.org,
open the gem's page and choose "Trusted publishers" (for a gem that has never been pushed, use
"Pending publishers" on your profile instead; a pending publisher reserves the name and expires
after 12 hours, so push the first tag within that window). Create a GitHub Actions publisher
with exactly these fields:

| Field | Value |
| --- | --- |
| Repository owner | `hvpaiva` |
| Repository name | `slipway` |
| Workflow filename | `release.yml` |
| Environment | `release` |

RubyGems matches the token by repository, workflow file and environment, so a workflow under
another name or without the environment is refused.

## Hotfixes and yanking

Only the latest release receives fixes ([SECURITY.md](SECURITY.md#supported-versions)). When
`main` already holds unreleased work that should not ship with the fix, release the fix from a
branch cut at the tag. With `0.3.0` as the latest release:

```sh
git switch -c hotfix/0.3 v0.3.0
git push -u origin hotfix/0.3
# commit the fix on a topic branch and merge it into hotfix/0.3 through a pull request,
# with its test and a changelog line under ## [Unreleased]
bin/release 0.3.1 --branch hotfix/0.3 --push
```

`--branch` makes `bin/release` compare the tree against that branch instead of `main` and open
the release pull request against it. Name the branch `hotfix/...`: the Release workflow
publishes a tag only when its commit is on `main` or on a `hotfix/*` branch. Afterwards, bring
the fix, `version.rb` and the new changelog section back to `main` in a normal pull request.
Release headings in `CHANGELOG.md` stay ordered newest first, so the `0.3.1` section sits
directly under `## [Unreleased]`, above `0.3.0`, and the entries still unreleased on `main` stay
under `## [Unreleased]`.

When a published version has to be pulled, release the fixed version first, then add
` [YANKED]` to the end of the pulled version's heading (`## [0.3.0] - 2026-10-01 [YANKED]`) with
a line saying why, in a normal pull request, and run `gem yank slipway -v 0.3.0`. The suffix is
the only change to the heading, so the changelog test, `rake release:verify` and the man page
date still read it. Yanking needs a personal RubyGems API key with MFA: the project
deliberately holds no key, and trusted publishing can only push.

## Dependency updates

Dependabot opens the pull requests described in `.github/dependabot.yml`: development gems
weekly and the pinned workflow actions monthly. They carry the `skip-changelog` label, because
the gem has no runtime dependencies and neither kind of update changes what users install. They
go through the same required checks as any other pull request and are merged by hand.
Security updates, titled `chore(deps): [security] bump ...` or `ci: [security] bump ...`, pass
the `commits` job as Dependabot writes them.

- A RuboCop bump that introduces new offenses is fixed in the same pull request, in the code,
  never with a disable or a new exclusion.
- A bump of `rubygems/release-gem` in `release.yml` can only be exercised by a real release, so
  read its changelog before merging and expect the next release to be its test.
