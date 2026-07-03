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
- `new <dir> [-t <template>]`  : Create a working directory from a template
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
- `version install [--native|--apptainer] [TAG]` : Install artemis (build from source or pull an Apptainer image)
- `version install --update <version>` : Re-pull the Apptainer image for an existing version
- `version help`               : Show the version group help

Template commands live under the `templates` group (see [Templates](#templates)):

- `templates ls`               : List available templates as `<repo>/<template>`
- `templates repos`            : List configured template repositories
- `templates update [repo...]` : Clone or update template repositories

Utility commands:

- `init`                       : Configure the shell environment for artenv
- `doctor [env|--all]`         : Diagnose a registered environment
- `migrate`                    : Migrate v1 (symlink) data to v2 (TOML)
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
```

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

### Configuring a template repository

Describe each repository in its own file, `template-repos/<name>.toml`:

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
artenv new /path/to/work -t artemis-templates/standard

# The repo prefix may be omitted when the name is unambiguous
artenv new /path/to/work -t standard
```

Without `-t`, `artenv new` prompts you to choose a template interactively.

### Local templates

Templates placed under `$ARTENV_ROOT/templates/local/` are available as
`local/<template>` without any repository. The `local` namespace is never
fetched, updated, or removed by artenv.

> `templates/` (clone caches and `local/`) and `template-repos/` are per-user
> runtime data and are gitignored.

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

## License
Copyright (c) 2026 Takayuki YANO

The source code is licensed under the MIT License, see LICENSE.
