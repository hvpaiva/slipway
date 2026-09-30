# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `get`, `describe`, `create`, `apply`, `delete`, `edit` and `label` verbs over two resource types, projects and groups, with kubectl's wording and result lines.
- Groups as namespaces: `-n`/`--group` scopes a command, `-A`/`--all-groups` covers every group, and the `default` group is created on first use. `-A` is refused next to explicit names, and `fetch`, `diff` and `sync` name their verb in the refusal (`cannot sync a project by name across all groups`).
- Label selectors on `get`, `describe`, `fetch`, `diff` and `sync`: `key=value`, `key!=value`, `key in (a,b)`, `key notin (a,b)`, `key` and `!key`, comma separated.
- Field selectors on `get` and `describe` with `--field-selector`: `path=value`, `path==value` and `path!=value`, comma separated, over `metadata.name`, `metadata.group`, `spec.path`, `status.state`, `status.branch` and `status.lastFetch` (`never` when no fetch is on record) of projects and `metadata.name` of groups. Values compare exactly, a field the object leaves out compares as the empty value, and a backslash escapes `\`, `,` and `=`.
- Output formats `table`, `wide`, `json`, `yaml` and `name`, plus `--no-headers` and `--show-labels`.
- One-word repository STATUS per project: Missing, NotARepo, Unsafe, Conflicted, Detached, Unborn, Dirty, Gone, Diverged, Ahead, Behind, Clean and Unknown, read from `git status --porcelain=v2`.
- `fetch` verb that runs `git fetch` in every selected project, up to `parallel` projects at once and without prompts, and reports each one as fetched, unchanged, skipped, denied or failed; a project with `spec.paused: true` is left alone and reported as paused, and `--prune` removes the remote-tracking refs of deleted branches.
- `sync` verb that fetches every selected project and fast-forwards the checked-out branch when it is clean and strictly behind its upstream, or up to a `spec.revision` pin its upstream holds and never back, and reports everything else with the git command that resolves it; `spec.syncPolicy: FetchOnly` only fetches and `spec.paused: true` leaves the project alone.
- `rollout history`, `rollout undo`, `rollout unpin`, `rollout pause` and `rollout resume`: slipway lists and reverts its own fast-forwards from the branch reflog, `undo` holds the project at the chosen revision through `spec.revision`, and pausing keeps fetch and sync away from a project.
- FETCHED column with the time since each repository was last fetched, or `<never>`, also shown as `Last Fetch` in `describe` and as `status.lastFetch` in json and yaml output.
- YAML manifests stored as plain files under `$XDG_DATA_HOME/slipway`, applied from files, directories or stdin with `apply -f`, one document or `kind: List` item at a time, and reported as created, configured or unchanged.
- `spec.remote`, `spec.branch`, `spec.revision`, `spec.syncPolicy` and `spec.paused` in project manifests, validated when a manifest is read and shown by `describe`, `-o json` and `-o yaml`.
- `create project --remote` and `--branch`, checked like the manifest fields they set.
- `diff` verb printing where each project differs from its manifest and what blocks sync, with the git command that shows or resolves it, without writing anything or contacting a remote; it exits with 3 when anything differs, and its man page has an EXIT STATUS section.
- Drift, where a repository differs from its manifest (Missing, Remote, Branch, Revision, Behind) and what blocks a fast-forward onto the upstream or up to a `spec.revision` pin the upstream holds, never back to it, in the DRIFT column of `-o wide`, in `status.drift` and in a Drift block of `describe`.
- `create -o name|yaml|json` prints the created resource instead of the result line; with `--dry-run` it prints the manifest without writing it.
- `--dry-run` on `apply`, `delete` and `label`, which print what they would change without writing it, and on `fetch`, `sync` and `rollout undo`, which contact no remote and change no repository.
- `delete --ignore-not-found`, and `label --overwrite` and `label --list`.
- `create project --from-dir DIR` registers every git repository at or under a directory, to `--depth` levels, named after its directory and with its origin URL stripped of credentials; a path already registered reports unchanged.
- `edit` through `SLIPWAY_EDITOR`, the `editor` config key, `VISUAL` or `EDITOR`, reopening the file with the failure as a comment when the result is invalid.
- Configuration file at `$XDG_CONFIG_HOME/slipway/config.yaml` with the keys `color`, `editor`, `group`, `networkTimeout`, `parallel`, `protocols` and `theme`, `SLIPWAY_*` environment variables, and `config view` and `config path`.
- Color per stream with `--color[=auto|always|never]`, `NO_COLOR`, `FORCE_COLOR` and `CLICOLOR_FORCE`, and `dark` and `light` themes following kubecolor.
- Shell completion for bash, zsh and fish that covers commands, flags, values and resource names.
- Bundled man pages for every command, with `slipway man`, `slipway man --path` and `slipway man --install[=DIR]`, which copies them into a `man1` directory; any other DIR, or a DIR after a space instead of `=`, is refused.
- Text from git is printed with control and bidirectional characters made visible, and credentials in URLs are masked in `describe`, in result details and in error lines.
- Exit statuses 0, 1, 2 and 130, `error:` lines on stderr with a help hint, "Did you mean this?" suggestions for unknown commands and flags, and `SLIPWAY_DEBUG`, which adds the class and backtrace of an unexpected error.
- `-V`/`--version` and `slipway version`.

[Unreleased]: https://github.com/hvpaiva/slipway/commits/main
