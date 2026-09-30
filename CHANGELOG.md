# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `get`, `describe`, `create`, `apply`, `delete`, `edit` and `label` verbs over two resource types, projects and groups, with kubectl's wording and result lines.
- Groups as namespaces: `-n`/`--group` scopes a command, `-A`/`--all-groups` lists across groups, and the `default` group is created on first use.
- Label selectors on `get`, `describe` and `fetch`: `key=value`, `key!=value`, `key in (a,b)`, `key notin (a,b)`, `key` and `!key`, comma separated.
- Field selectors on `get` and `describe` with `--field-selector`: `path=value`, `path==value` and `path!=value`, comma separated, over `metadata.name`, `metadata.group`, `spec.path`, `status.state`, `status.branch` and `status.lastFetch` (`never` when no fetch is on record) of projects and `metadata.name` of groups.
- Output formats `table`, `wide`, `json`, `yaml` and `name`, plus `--no-headers` and `--show-labels`.
- One-word repository STATUS per project: Missing, NotARepo, Unsafe, Conflicted, Detached, Unborn, Dirty, Gone, Diverged, Ahead, Behind, Clean and Unknown, read from `git status --porcelain=v2` on a bounded thread pool.
- `fetch` verb that runs `git fetch` in every selected project on a bounded pool, without prompts, and reports each one as fetched, unchanged, skipped, denied or failed; a project with `spec.paused: true` is left alone and reported as paused.
- FETCHED column with the time since each repository was last fetched, or `<never>`, also shown as `Last Fetch` in `describe` and as `status.lastFetch` in json and yaml output.
- YAML manifests stored as plain files under `$XDG_DATA_HOME/slipway`, applied from files, directories or stdin with `apply -f`, and reported as created, configured or unchanged.
- `spec.remote`, `spec.branch`, `spec.revision`, `spec.syncPolicy` and `spec.paused` in project manifests, validated when a manifest is read and shown by `describe`, `-o json` and `-o yaml`.
- `create project --remote` and `--branch`, checked like the manifest fields they set.
- `diff` verb printing where each project differs from its manifest and what blocks sync, with the git command that shows or resolves it, without writing anything or contacting a remote; it exits with 3 when anything differs, and its man page has an EXIT STATUS section.
- Drift, where a repository differs from its manifest (Missing, Remote, Branch, Revision, Behind) and what blocks a fast-forward, in the DRIFT column of `-o wide`, in `status.drift` and in a Drift block of `describe`.
- `edit` through `SLIPWAY_EDITOR`, the `editor` config key, `VISUAL` or `EDITOR`, reopening the file with the failure as a comment when the result is invalid.
- Configuration file at `$XDG_CONFIG_HOME/slipway/config.yaml` with the keys `color`, `editor`, `group`, `networkTimeout`, `parallel`, `protocols` and `theme`, `SLIPWAY_*` environment variables, and `config view` and `config path`.
- Color per stream with `--color[=auto|always|never]`, `NO_COLOR`, `FORCE_COLOR` and `CLICOLOR_FORCE`, and `dark` and `light` themes following kubecolor.
- Shell completion for bash, zsh and fish that covers commands, flags, values and resource names.
- Bundled man pages for every command, with `slipway man`, `slipway man --path` and `slipway man --install[=DIR]`, which copies them into a `man1` directory; any other DIR, or a DIR after a space instead of `=`, is refused.
- Text from git is printed with control and bidirectional characters made visible, and credentials in URLs are masked in `describe` and in error lines.
- Exit statuses 0, 1, 2 and 130, `error:` lines on stderr with a help hint, and "Did you mean this?" suggestions for unknown commands.

[Unreleased]: https://github.com/hvpaiva/slipway/commits/main
