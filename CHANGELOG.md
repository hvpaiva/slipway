# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `get`, `describe`, `create`, `apply`, `delete`, `edit` and `label` verbs over two resource types, projects and groups, with kubectl's wording and result lines.
- Groups as namespaces: `-n`/`--group` scopes a command, `-A`/`--all-groups` lists across groups, and the `default` group is created on first use.
- Label selectors on `get` and `describe`: `key=value`, `key!=value`, `key in (a,b)`, `key notin (a,b)`, `key` and `!key`, comma separated.
- Output formats `table`, `wide`, `json`, `yaml` and `name`, plus `--no-headers` and `--show-labels`.
- One-word repository STATUS per project: Missing, NotARepo, Unsafe, Conflicted, Detached, Unborn, Dirty, Gone, Diverged, Ahead, Behind, Clean and Unknown, read from `git status --porcelain=v2` on a bounded thread pool.
- YAML manifests stored as plain files under `$XDG_DATA_HOME/slipway`, applied from files, directories or stdin with `apply -f`, and reported as created, configured or unchanged.
- `edit` through `SLIPWAY_EDITOR`, the `editor` config key, `VISUAL` or `EDITOR`, reopening the file with the failure as a comment when the result is invalid.
- Configuration file at `$XDG_CONFIG_HOME/slipway/config.yaml` with the keys `color`, `editor`, `group` and `theme`, `SLIPWAY_*` environment variables, and `config view` and `config path`.
- Color per stream with `--color[=auto|always|never]`, `NO_COLOR`, `FORCE_COLOR` and `CLICOLOR_FORCE`, and `dark` and `light` themes following kubecolor.
- Shell completion for bash, zsh and fish that covers commands, flags, values and resource names.
- Bundled man pages for every command, with `slipway man`, `slipway man --install` and `slipway man --path`.
- Text from git is printed with control and bidirectional characters made visible, and credentials in URLs are masked in `describe` and in error lines.
- Exit statuses 0, 1, 2 and 130, `error:` lines on stderr with a help hint, and "Did you mean this?" suggestions for unknown commands.

[Unreleased]: https://github.com/hvpaiva/slipway/commits/main
