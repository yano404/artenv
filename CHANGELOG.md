# Changelog

All notable changes to artenv are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **`edit`** (`artenv edit [env]` / `artenv version edit [version]`) — open a
  resource's TOML config in `$VISUAL`/`$EDITOR`, validating it as TOML on save.

### Changed

- **Breaking:** renamed `artenv doctor --hygiene` to
  **`artenv doctor --orphans`**. The old `--hygiene` flag is removed and now
  errors (`unknown option`). The scan is report-only; `--orphans` names what it
  finds. `--hygiene` existed only in 2.1.0 (renamed the same day), so no
  deprecation alias is kept. Per artenv's theme-based versioning (see
  [Versioning](README.md#versioning)), this within-theme refinement ships as a
  minor release rather than a major bump.

### Fixed

- `artenv version register` / `artenv register` now abort cleanly on stdin EOF
  (non-interactive input / Ctrl-D) instead of crashing with
  `tmp_conf: unbound variable`.

## [2.1.0] - 2026-07-04

Resource-grouped command taxonomy. This release is additive and backward
compatible: every old command name still works as a deprecated alias.

### Added

- **`version` command group** — `artenv version <cmd>`: `ls`, `register`,
  `remove`, `archive`, `unarchive`, `info`, `install`, `current`. Bare
  `artenv version` still prints the current version.
- **`templates` command group** — manage project templates from external git
  repositories: `artenv templates ls` / `repos` / `update`. Repositories are
  configured under `template-repos/<name>.toml` and cached under
  `templates/<repo>/`. Ships with a default repository
  ([artemis-templates](https://github.com/yano404/artemis-templates)) so
  `artenv templates update` works out of the box.
- **Implicit env commands** — env is the default resource: `artenv ls`,
  `register`, `remove`, `archive`, `unarchive`, `info`, `new`.
- **`remove`** (`version remove` / `remove`) — with `--force`, `--purge`
  (delete the SIF under `images/`), `--yes`, and reference checks that block
  removing a version still used by an environment.
- **`archive` / `unarchive`** (version and env) — non-destructive, reversible
  retirement. Archived entries are hidden from `ls` / `version ls` unless
  `-a`/`--all` is given.
- **`doctor --hygiene`** — store-wide scan for orphaned resources: unreferenced
  `.sif` images, environments pointing at a missing version, and orphan
  `*.artlogin.sh` files. (Renamed to `--orphans` after this release; see
  Unreleased.)
- **`version info`** — show a registered version's configuration.
- **`new -t [<repo>/]<name>`** — create a project from a named template.
- **Cold-start hint** — `new` / `templates ls` guide the user to run
  `artenv templates update` when no templates are cached yet.
- **Continuous integration** — GitHub Actions runs the test suite and
  shellcheck (both required) on every push and pull request.

### Changed

- Consistent `-h`/`--help` across all user-facing commands: each prints its
  usage and exits 0.
- The bundled `templates/standard` template was removed in favour of the
  external default template repository.

### Deprecated

- The flat command names `versions`, `register-version`, `remove-version`,
  `archive-version`, `unarchive-version`, `install`, `register-env`,
  `remove-env`, `archive-env`, `unarchive-env` now print a one-line notice to
  stderr pointing at their grouped/implicit replacement. Set
  `ARTENV_NO_DEPRECATION=1` to silence them. They remain fully functional and
  are scheduled for removal in a future major release.

### Fixed

- `version info` exited non-zero for apptainer versions without a `digest`.
- `version register` / `register` no longer crash when given `-h`.

## [2.0.0] - 2026-06-26

### Added

- Apptainer container support with shell-function wrappers.
- `artenv install` (`--native` / `--apptainer` / `--update` / `--list`),
  replacing `artenv make`.
- `artenv migrate` to convert v1 (symlink-based) data to v2.

### Changed

- Configuration migrated from symlinks to TOML
  (`versions/<name>.toml`, `envs/<name>.toml`), read via `yq`. The Python
  dependency was dropped.

## [1.0.0]

- Initial release (symlink-based version/environment management).

[Unreleased]: https://github.com/yano404/artenv/compare/v2.1.0...HEAD
[2.1.0]: https://github.com/yano404/artenv/compare/v2.0.0...v2.1.0
[2.0.0]: https://github.com/yano404/artenv/compare/v1.0.0...v2.0.0
[1.0.0]: https://github.com/yano404/artenv/releases/tag/v1.0.0
