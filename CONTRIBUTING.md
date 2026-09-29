# Contributing

Thanks for taking the time. This page covers the workflow; [ARCHITECTURE.md](ARCHITECTURE.md)
explains where things live and how to add a verb, an option, a completer or a theme role.

## Setup

You need Ruby 3.4 or newer (the repository pins 4.0.7 in `mise.toml`), git 2.35 or newer, and
for the optional checks `groff`, `shellcheck`, `zsh` and `fish`.

```sh
git clone https://github.com/hvpaiva/slipway.git
cd slipway
bin/setup
bundle exec ruby -Ilib exe/slipway --help
```

`bin/setup` runs `bundle install`. `bin/console` opens IRB with the gem loaded.

## Tests and lint

```sh
bundle exec rake            # tests and RuboCop; CI runs these and the tasks below
bundle exec rake test       # tests only, with Ruby warnings on
bundle exec rake test:cov   # with SimpleCov and branch coverage
bundle exec rake rubocop
bundle exec rake lint:man   # groff -ww over man/man1
bundle exec rake lint:shell # ShellCheck over bin/setup and the bash completion script
bundle exec rake audit      # bundler-audit against a fresh advisory database
```

Tests that need a tool you do not have (`shellcheck`, `groff`, `zsh`, `fish`) skip themselves
and say why. The `completions` job on CI sets `SLIPWAY_REQUIRE_SHELLS=1` so a missing `zsh`
or `fish` fails there instead of skipping; every other job skips the way a local run does. The
lint job runs `shellcheck` and `groff` directly. Everything runs against temporary directories
and repositories created for the test, never against your own registry.

## Conventions

- RuboCop must pass with the configuration in `.rubocop.yml`: the defaults with `NewCops:
  enable`, the minitest, performance and rake plugins, single quotes, and the `Metrics` limits
  set there. Do not add inline `rubocop:disable` comments; if a method outgrows the limits,
  split it.
- Every Ruby file starts with `# frozen_string_literal: true`. Requires inside the gem use
  `require_relative`.
- Every public class and module carries a one-sentence comment saying what it is for.
  Comments explain intent or a constraint, never what the code already says.
- Every change ships with tests. A bug fix starts with a test that fails; a new option or verb
  gets unit tests in `test/unit/commands` and, when it prints something, an exact-output
  assertion.
- User-visible text follows kubectl's wording: `project/hldr created`, `No resources found in
  work group.`, `error: projects "hldr" not found`. When kubectl has a phrase for the situation,
  use it. Everything is in English, without emoji.
- No new runtime dependencies. The gem runs on the standard library alone.

## Generated files

`man/man1/*.1` is generated from the command definitions. After changing a command, an option,
a description or an example, run

```sh
bundle exec rake generate
bundle exec rake lint:man
```

and commit the pages with the change. CI regenerates them and fails when the committed pages
differ. The page date comes from the newest `## [x.y.z] - YYYY-MM-DD` heading in
`CHANGELOG.md`, so a plain change does not touch the date. The completion scripts are not
generated files; `rake lint:shell` runs ShellCheck over the bash one as `slipway completion bash`
prints it.

Help pages, completion scripts and man pages also have golden files under
`test/fixtures/golden` and `man/man1`. When a text change is intended, run
`UPDATE_GOLDEN=1 bundle exec rake test` once, review the diff, and commit the fixtures with it.

## Testing completions

The completion scripts are tested in real shells by `test/unit/cli/completion_scripts_test.rb`.
Locally, bash is always exercised (with and without `bash-completion` when
`/usr/share/bash-completion/bash_completion` exists). To try a script by hand:

```sh
eval "$(bundle exec ruby -Ilib exe/slipway completion bash)"
slipway get <TAB>
```

For zsh and fish, install them or run the suite in a container so the skipped tests execute.
`SLIPWAY_REQUIRE_SHELLS=1` turns a missing shell into a failure, which is how the CI
`completions` job runs and how you can be sure nothing was skipped:

```sh
docker run --rm -v "$PWD:/src" -w /src ruby:4.0 \
  bash -c 'apt-get update -q && apt-get install -y -q zsh fish shellcheck groff && bin/setup && SLIPWAY_REQUIRE_SHELLS=1 bundle exec rake test'
```

## Commits

- Conventional Commits in English and the imperative: `feat: add the label verb`,
  `fix: prune the group directory after the last delete`, `docs:`, `test:`, `refactor:`,
  `chore:`, `ci:`.
- One change per commit, with its tests and generated files. No "WIP" or "fixup" commits in a
  pull request.
- Commits are signed by their author (`git commit -S`, or SSH signing).
- Attribution trailers for tools (`Co-Authored-By` lines naming an assistant, `Generated-by`,
  and the like) are not accepted, in commits or in pull request descriptions.

## Pull requests

- Open an issue first for anything larger than a fix, so the shape can be agreed before the
  code exists.
- Keep the pull request to one subject. Describe what changed and how you tested it; the
  template asks for both.
- `bundle exec rake` must be green, generated files must be current, and user-visible changes
  get a line under `## [Unreleased]` in `CHANGELOG.md`.
- Expect review comments on wording as much as on code; the help texts and messages are part
  of the interface.

## Releasing

Releases are cut from `main` by a maintainer.

1. Set the new version in `lib/slipway/version.rb`.
2. In `CHANGELOG.md`, move the `## [Unreleased]` notes under `## [X.Y.Z] - YYYY-MM-DD` (today's
   date), leave an empty `## [Unreleased]` above it, and update the link references at the
   bottom: `[Unreleased]` compares `vX.Y.Z...HEAD` and `[X.Y.Z]` points at the release tag.
3. Run `bundle exec rake generate` so the man pages carry the release date, then
   `bundle exec rake` and `bundle exec rake lint:man`.
4. Commit as `chore: release vX.Y.Z`, tag it and push the tag:

   ```sh
   git tag -a vX.Y.Z -m "vX.Y.Z"
   git push origin main vX.Y.Z
   ```

The tag starts the release workflow (`.github/workflows/release.yml`). It checks that the tag
matches `Slipway::VERSION` and that the changelog has a section for it, runs the suite, builds
the gem and publishes it to RubyGems through trusted publishing (no API key is stored anywhere;
the job gets a short-lived OIDC token in the `release` environment), then creates the GitHub
release with the changelog section as its notes. Do not run `rake release` locally.

### One-time setup of the trusted publisher

On rubygems.org, open the gem's page and choose "Trusted publishers" (for a gem that has never
been pushed, use "Pending publishers" on your profile instead; a pending publisher reserves the
name and expires after 12 hours, so push the tag soon after creating it). Create a GitHub
Actions publisher with exactly these fields:

| Field | Value |
| --- | --- |
| Repository owner | `hvpaiva` |
| Repository name | `slipway` |
| Workflow filename | `release.yml` |
| Environment | `release` |

Then create the `release` environment in the GitHub repository settings and restrict its
deployment branches and tags to `v*`. RubyGems matches the token by repository, workflow file
and environment, so a workflow under another name or without the environment is refused.
