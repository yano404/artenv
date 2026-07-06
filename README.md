artenv
======

artenv is the version and environment manager tool for [Artemis](https://github.com/artemis-dev/artemis).
artenv enables you to switch multiple artemis versions and analysis environments easily.
Both native installations and [Apptainer](https://apptainer.org/) container images are supported as artemis versions.

Commands are organised by resource: environment commands are typed directly
(`artenv register`, `artenv ls`, ...), while versions and templates live under
their own groups (`artenv version <cmd>`, `artenv templates <cmd>`). The older
flat names (`register-env`, `versions`, `install`, ...) still work as
deprecated aliases.

## Requirements

- bash
- git (used to fetch project templates)
- yq v4 with TOML support (`dnf install yq` on RHEL/Fedora; or download from [github.com/mikefarah/yq](https://github.com/mikefarah/yq/releases))

## Installation

```sh
git clone https://github.com/yano404/artenv.git ~/.artenv
```

## Setup

### 1. Shell configuration

Add to your `.bashrc` or `.zshrc` :

```
export ARTENV_ROOT="$HOME/.artenv"
export PATH="$ARTENV_ROOT/bin:$PATH"
eval "$(artenv init -)"
```

Restart your shell.

```sh
exec $SHELL
```

### 2. Install Artemis

Choose one of the following depending on your use case.

#### Apptainer (recommended)

Pull the Artemis container image and register it as a version:

```sh
artenv version install latest
```

Available tags can be listed with:

```sh
artenv version install --list
```

#### Native (existing installation)

If you have already built Artemis from source, register it manually:

```sh
artenv version register <version-name>
Select version type
1) native
2) apptainer
#? 1
Enter the path to artemis> /path/to/artemis
Enter the path to root> /path/to/root
Enter the path to yaml-cpp> /path/to/yaml-cpp
<version-name> was registered
```

### 3. Register analysis environment

```sh
artenv register <env-name>
Select the artemis version
1) artemis-vXXX
2) artemis-vYYY
#? 2
artemis-vYYY was selected
Enter the path to working directory> /path/to/analysis_directory
Use artlogin? (y/n)> y
Enter the path to git repos (required)> /path/to/git_repos or URL of git repos
<env-name> was registered
```

Each field can also be supplied via a flag, so the command can run
non-interactively (for HPC/batch jobs and scripting):

```sh
artenv register <env-name> \
  --version artemis-vYYY \
  --work /path/to/analysis_directory \
  --singleuser
```

Flags:

- `--version <version>` — Artemis version to use (must be registered and not
  archived).
- `--work <dir>` — path to the working directory (must exist).
- `--repos <url|path>` — git repos location. Stored raw, so a URL stays a URL.
  Required together with `--multiuser`.
- `--multiuser` — multi-user environment: enable artlogin
  (`use_artlogin = true`).
- `--singleuser` — single-user environment: disable artlogin
  (`use_artlogin = false`).

Resolution is per field: a flag wins; otherwise, on a tty, the omitted field
falls back to its interactive prompt; otherwise a sensible default is used
(single-user, no git repos) or the command exits asking for the missing flag.
A bare `artenv register <env-name>` on a tty is unchanged — it prompts for
every field exactly as before.

When it is not a tty, `--version` and `--work` are required (there is nothing
to prompt); artlogin defaults to single-user unless `--multiuser` is given.

### 4. Fetch project templates

Fetch the template repositories once so that `artenv new` can scaffold from
them:

```sh
artenv templates update
```

This clones the configured repositories (the bundled default is
[artemis-templates](https://github.com/yano404/artemis-templates)) into a
local cache. Re-run it whenever you want to update. See [Templates](#templates).

## Shell Completions

`artenv` provides shell completion for both bash and zsh.

### Bash

Source the completion script from your `.bashrc` :

```
source "${ARTENV_ROOT}/completions/artenv.bash"
```

### Zsh

Add the completions directory to fpath and initialize completion in your `.zshrc` :

```zsh
fpath=("${ARTENV_ROOT}/completions" $fpath)
autoload -Uz compinit
compinit
```

## Commands

Environment commands operate on the implicit "environment" resource and are
typed directly:

- `register [env]`             : Register an analysis environment
- `remove [env]`               : Remove a registered environment
- `archive [env]`              : Archive an environment (hidden from `ls`, still usable)
- `unarchive [env]`            : Unarchive an environment
- `ls [-a|--all]`              : Print the environment list (`--all` includes archived)
- `info [env]`                 : Print the detail information of an environment
- `edit [env]`                 : Open an environment's config in $EDITOR
- `new <dir> [-t <template>]`  : Create a working directory from a template
- `new --multiuser <dest> [--repo <repo>] -t <template>` : Set up a shared multi-user project skeleton (see [Multi-user projects](#multi-user-projects-artenv-new---multiuser))
- `shell [env]`                : Set or show the activated environment in the current shell
- `default [env]`              : Set or show the default environment

Version commands live under the `version` group:

- `version`                    : Print the current artemis version
- `version current`            : Print the current artemis version
- `version ls [-a|--all]`      : Print the registered artemis versions
- `version register <version>` : Register an artemis version
- `version remove [version]`   : Remove a registered artemis version
- `version archive [version]`  : Archive a version (hidden from `version ls`, still usable)
- `version unarchive [version]`: Unarchive a version
- `version info [version]`     : Show the configuration of a version (defaults to the current one)
- `version edit [version]`     : Open a version's config in $EDITOR
- `version install [--native|--apptainer] [TAG]` : Install artemis (build from source or pull an Apptainer image)
- `version install --update <version>` : Re-pull the Apptainer image for an existing version
- `version help`               : Show the version group help

Template commands live under the `templates` group (see [Templates](#templates)):

- `templates ls`               : List available templates as `<repo>/<template>`
- `templates repos`            : List configured template repositories
- `templates update [repo...]` : Clone or update template repositories

Utility commands:

- `init`                       : Configure the shell environment for artenv
- `doctor [env|--all|--orphans]` : Diagnose environments / scan store health
- `migrate`                    : Migrate v1 (symlink) data to v2 (TOML)
- `upgrade`                    : Update artenv itself to the latest release (see [Upgrading](#upgrading))
- `commands`                   : List all available commands
- `--version`                  : Show the version of artenv

### Deprecated aliases

The following older names still work but are deprecated; prefer the grouped
forms above.

| alias | equivalent |
|---|---|
| `versions` | `version ls` |
| `register-version` | `version register` |
| `remove-version` | `version remove` |
| `archive-version` | `version archive` |
| `unarchive-version` | `version unarchive` |
| `install` | `version install` |
| `register-env` | `register` |
| `remove-env` | `remove` |
| `archive-env` | `archive` |
| `unarchive-env` | `unarchive` |

Each alias prints a one-line deprecation notice to stderr (stdout is
unaffected, so pipelines keep working). Set `ARTENV_NO_DEPRECATION=1` to
silence the notices.

### Examples

- `artenv ls`

```
$ artenv ls
  artdev
  e545
* e559
  h424
```

- `artenv version ls`

```
$ artenv version ls
* artemis-e559
  artemis-root-6.26.10
  develop
```

- `artenv version` (current version)

```
$ artenv version
artemis-e559
```

- `artenv info` (native environment)

```
- env: e559
- artemis version: artemis-e559
  - artemis: /home/quser/local/artemis/artemis-e559 [OK]
  - root: /home/quser/local/root/v6.26.10 [OK]
  - yaml-cpp lib: /home/quser/local/yaml-cpp/yaml-cpp-0.6.3/lib [OK]
  - yaml-cpp cmake: /home/quser/local/yaml-cpp/yaml-cpp-0.6.3/lib/cmake [OK]
- analysis directory: /home/yano/work/e559/art [OK]
- working directory: /home/yano/work/e559/art [OK]
- git repository:
- use artlogin: NO
```

- `artenv shell`

```
$ artenv shell e559
$ echo $PATH
/home/quser/local/artemis/artemis-e559/bin:/home/quser/local/root/v6.26.10/bin:/home/yano/local/artenv/libexec
$ artenv shell artdev
$ echo $PATH
/home/yano/local/artemis/develop/bin:/home/yano/local/root/v6.32.04/bin:/home/yano/local/artenv/libexec
```

- `artenv version install`

Native (build from source):

```
$ artenv version install --native
Enter the path to root> /home/yano/local/root/v6.32.04
Enter the path to yaml-cpp> /home/yano/local/yaml-cpp/v0.8.0
Enter the path to the source of artemis> /home/yano/src/artemis/develop
Enter the path to build directory> /home/yano/build/artemis/artdev
Enter the install prefix> /home/yano/local/artemis/artdev
Configuration:
  ROOTSYS                /home/yano/local/root/v6.32.04
  YAML_CPP_LIB           /home/yano/local/yaml-cpp/v0.8.0/lib
  YAML_CPP_CMAKE         /home/yano/local/yaml-cpp/v0.8.0/lib/cmake
  ARTEMIS_SOURCE         /home/yano/src/artemis/develop
  BUILD_DIR              /home/yano/build/artemis/artdev
  INSTALL_PREFIX         /home/yano/local/artemis/artdev
OK? (y/N)> y
```

Apptainer (pull image):

```
$ artenv version install --apptainer
Enter the pull URI [oras://ghcr.io/yano404/artemis_apptainer:latest]>
Enter the version name> artemis-latest
Enter the path to save SIF [/home/yano/.artenv/images/artemis-latest.sif]>
Configuration:
  URI                    oras://ghcr.io/yano404/artemis_apptainer:latest
  VERSION                artemis-latest
  SIF                    /home/yano/.artenv/images/artemis-latest.sif
OK? (y/N)> y
```

Update (re-pull when the upstream image changes):

```
$ artenv version install --update artemis-latest
Checking registry...
Update:
  VERSION                artemis-latest
  URI                    oras://ghcr.io/yano404/artemis_apptainer:latest
  SIF                    /home/yano/.artenv/images/artemis-latest.sif
  DIGEST                 sha256:121ea823...
OK? (y/N)> y
```

- `artenv version remove` / `artenv remove`

```
$ artenv remove e559
Remove environment 'e559'? (y/N)> y
e559 was removed

$ artenv version remove artemis-e559
artenv: version 'artemis-e559' is used by the following environments:
  - e545
remove these environments first, or use --force
```

Remove the SIF image together with an Apptainer version:

```
$ artenv version remove --purge artemis-latest
Remove version 'artemis-latest'? (y/N)> y
removed image: /home/yano/.artenv/images/artemis-latest.sif
artemis-latest was removed
```

- `artenv archive` / `artenv version archive`

Archiving is a non-destructive, reversible way to retire a version or
environment. An archived entry is hidden from the default `artenv ls` /
`artenv version ls` listing, but it can still be resolved and activated, and it
is never deleted. Use `-a`/`--all` to see archived entries, and `unarchive`
to bring them back.

```
$ artenv archive e545
e545 was archived

$ artenv ls
* e559
  h424

$ artenv ls --all
  e545 (archived)
* e559
  h424

$ artenv unarchive e545
e545 was unarchived
```

- `artenv doctor`

```
artenv doctor           # checks the current environment
artenv doctor <env>     # checks the specified environment
artenv doctor --all     # checks all registered environments
artenv doctor --orphans # store-wide scan for orphaned resources
```

`--orphans` performs a store-wide scan and reports leftovers that `remove` /
`archive` can leave behind: unreferenced `.sif` images under `images/`,
environments pointing at a version that no longer exists, and orphaned
`*.artlogin.sh` files (no matching env, or `use_artlogin = false`). It exits
non-zero when any issue is found.

- `artenv migrate`

Migrate v1 (symlink-based) data to v2 (TOML-based):

```
artenv migrate
```

## Templates

`artenv new` scaffolds a working directory from a template. Templates are
provided by external git repositories, cloned into a local cache under
`$ARTENV_ROOT/templates/<repo>/`. Templates are addressed as
`<repo>/<template>`.

artenv ships with a default repository, [artemis-templates](https://github.com/yano404/artemis-templates),
so `artenv templates update` followed by `artenv new <dir> -t default/standard`
works out of the box.

### Configuring a template repository

Each repository is described in its own file, `template-repos/<name>.toml`.
The bundled default, `template-repos/default.toml`, is created automatically
on first run (seeded from `share/template-repos/default.toml`). This runtime
file is gitignored and yours to edit freely — changes are never overwritten by
`git pull` upgrades. To add another repository, create a new file:

```toml
[repo]
url         = "https://github.com/yano404/artemis-templates.git"  # required
enabled     = true          # optional (default: true)
ref         = "main"        # optional: branch, tag, or commit to check out
description = "Artemis analysis templates"                        # optional
```

The repository's top-level directories are its templates. Authentication for
private repositories is handled by git itself (SSH keys / credential helper);
artenv never stores credentials.

### Fetching and using templates

```sh
# Clone / update the configured repositories into the local cache
artenv templates update

# List configured repositories
artenv templates repos

# List available templates as <repo>/<template>
artenv templates ls

# Create a working directory from a template
artenv new /path/to/work -t default/standard

# The repo prefix may be omitted when the name is unambiguous
artenv new /path/to/work -t standard
```

Without `-t`, `artenv new` prompts you to choose a template interactively.

### Local templates

Templates placed under `$ARTENV_ROOT/templates/local/` are available as
`local/<template>` without any repository. The `local` namespace is never
fetched, updated, or removed by artenv.

> `templates/` (clone caches and `local/`) and `template-repos/` are per-user
> runtime data and are gitignored. `template-repos/default.toml` is seeded on
> first run from the bundled `share/template-repos/default.toml`, so editing it
> never dirties the working tree or conflicts on upgrade.

### Multi-user projects (`artenv new --multiuser`)

For a project shared by several users, `artenv new --multiuser` sets up the
skeleton: an empty, group-shared analysis directory plus a seeded upstream git
repository that everyone clones from. It is a **two-step** flow — `new
--multiuser` does *not* register an environment; it prints the `register`
command to run next.

**Step 1 — create the shared skeleton:**

```sh
artenv new --multiuser /shared/myproject -t default/standard
```

This creates two artifacts:

- **`/shared/myproject`** — an empty directory with mode `2770` (setgid +
  group `rwx`, no world access). The setgid bit means files created inside
  inherit the directory's group, so collaborators can read and write each
  other's work; set your `umask` to `007` (or `002`) so new files stay
  group-writable. The directory must be absent or empty beforehand — `artenv`
  refuses a non-empty target. **The template does not go here.**
- **the upstream repo** — a bare repository created with
  `git init --bare --shared=group` on branch `main`, seeded from the template.
  It defaults to `/shared/myproject/myproject.git`; pass `--repo <path>` to put
  it elsewhere. **The template lands only in this repo.**

MVP is **local bare repositories only**: a `--repo` that looks like a URL or an
`scp`-style `user@host:path` destination is rejected with "remote destinations
are not yet supported; use a local path". `-t <template>` is required in
multiuser mode.

**Step 2 — register an environment** pointing `--work` at the shared directory
and `--repos` at the upstream repo (the command is printed for you):

```sh
artenv register myproject --version <version> \
  --work /shared/myproject --repos /shared/myproject/myproject.git --multiuser
```

**Step 3 — each user logs in.** With the multi-user (artlogin) environment
active, `artlogin <name>` clones the upstream repo into a per-user subdirectory
of the shared directory, so everyone works from their own checkout of the same
history.

## Configuration Files

artenv stores version and environment settings as TOML files under `$ARTENV_ROOT`.

### Version config (`versions/<name>.toml`)

**Native:**

```toml
[version]
type = "native"
artsys    = "/path/to/artemis"
rootsys   = "/path/to/root"
yamllib   = "/path/to/yaml-cpp/lib"
yamlcmake = "/path/to/yaml-cpp/cmake"
```

**Apptainer:**

```toml
[version]
type   = "apptainer"
uri    = "oras://ghcr.io/yano404/artemis_apptainer:latest"  # pull URI (set by artenv version install)
image  = "/path/to/artemis.sif"
digest = "sha256:..."                                         # manifest digest (set by artenv version install, used by --update)
```

### Environment config (`envs/<name>.toml`)

```toml
[env]
version      = "version-name"          # registered version name (required)
work         = "/path/to/work"         # working directory (required)
git_repos    = "/path/to/git_repos"   # git repository path or URL (optional)
use_artlogin = false                   # enable artlogin (optional, default: false)
binds        = ["/extra/path"]         # additional Apptainer bind paths (optional)
```

`binds` is only used when the referenced version is of type `apptainer`.

### Template repo config (`template-repos/<name>.toml`)

See [Templates](#templates).

## Apptainer Support

When an Apptainer environment is active, the following commands are automatically wrapped to run inside the container:

- `artemis`
- `cmake`
- `make`
- `root`
- `artexec` — runs an arbitrary command inside the container

```sh
# Run any command inside the Apptainer container
artexec ./make.sh
artexec bash
artexec which root
```

The working directory (`ART_WORK_DIR`) is automatically bind-mounted into the container.
Additional bind paths can be specified in the environment config (`envs/<env-name>.toml`):

```toml
[env]
version = "artemis-apptainer"
work = "/path/to/work"
binds = ["/extra/path1", "/extra/path2"]
```

## Upgrading

To update artenv itself to the latest release, run:

```sh
artenv upgrade
```

This fetches tags from the remote and checks out the newest `vX.Y.Z` tag,
leaving the checkout on a **detached HEAD** at that tag — this is normal and
expected.

Only artenv's tracked core files are updated. All runtime data — `versions/`,
`envs/`, `env`, `templates/`, `template-repos/`, `images/` — is gitignored and
never touched. Thanks to the seed pattern, even `template-repos/default.toml` is
untracked (the bundled copy lives at `share/template-repos/default.toml` and is
copied into place on first run), so as long as you have not hand-edited any
tracked core file, `artenv upgrade` updates cleanly.

`artenv upgrade` never stashes. If you have local changes to tracked files it
fails fast rather than touching your edits. To upgrade anyway, stash them first
and reapply afterwards:

```sh
git -C "$ARTENV_ROOT" stash
artenv upgrade
git -C "$ARTENV_ROOT" stash pop
```

(This is the general form of the `git pull` conflict note from the v2.2.1
upgrade instructions.)

In an Apptainer setup, `artenv upgrade` updates only the artenv code. It does
**not** re-pull container images; update those separately with
`artenv version install --update <version>`.

## Versioning

artenv's **major** version tracks broad themes rather than strict per-flag
[SemVer](https://semver.org/): a change that stays within the current major's
theme ships as a minor/patch release, even if it is technically a breaking
change to the command surface. As an end-user CLI (not a library consumed by a
dependency resolver), the changelog is the source of truth for what changed —
so always read [CHANGELOG.md](CHANGELOG.md), not just the major number, when
upgrading.

**v2** covers three themes:

1. Configuration migrated from symlinks to TOML (`versions/*.toml`, `envs/*.toml`).
2. Apptainer support and the resource-grouped command taxonomy (`version` /
   `templates` groups, implicit env commands, deprecated aliases).
3. Templates managed via external git repositories.

The next major (**v3**) is reserved for the next thematic shift beyond these.

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for the release history.

## License
Copyright (c) 2026 Takayuki YANO

The source code is licensed under the MIT License, see LICENSE.
