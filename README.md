artenv
======

artenv is the version and environment manager tool for [Artemis](https://github.com/artemis-dev/artemis).
artenv enables you to switch multiple artemis versions and analysis environment easily.

## Installation

```sh
git clone https://github.com/yano404/artenv.git ~/.artenv
```

## Setup

Add to `.bashrc` or `.zshrc` :

```sh
export ARTENV_ROOT="$HOME/.artenv"
export PATH="$ARTENV_ROOT/bin:$PATH"
eval "$(artenv init)"
```

Restart your shell.

```sh
exec $SHELL
```

Register artemis:

```sh
artenv register-version <version-name>
Enter the path to artemis> /path/to/artemis
Enter the path to root> /path/to/root
Enter the path to yaml-cpp> /path/to/yaml-cpp
<version-name> was registered
```

Register analysis environment:

```sh
artenv register-env <env-name>
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

## Commands

- `ls`               : Print the environment lis
- `versions`         : Print the artemis versions
- `version`          : Print the current artemis version
- `info`             : Print the detail information of environment
- `shell`            : Set or show the activated environment in the current shell
- `default`          : Set or show the default environment
- `init`             : Configure the shell environment for artenv
- `--version`        : Show the version of artenv
- `register-version` : Register a artemis version
- `register-env`     : Register analysis environment
- `new`              : Create the working directory using the templates
- `make`             : Install artemis to your environment

### Examples

- `artenv ls`

```
$ artenv ls
  artdev
  e545
* e559
  h424
```

- `artenv versions`

```
$ artenv versions
* artemis-e559
  artemis-root-6.26.10
  develop
```

- `artenv version`

```
$ artenv version
artemis-e559
```

- `artenv info`

```
- env: e559
- artemis version: artemis-e559
  - artemis: /home/quser/local/artemis/artemis-e559
  - root: /home/quser/local/root/v6.26.10
  - yaml-cpp: /home/quser/local/yaml-cpp/yaml-cpp-0.6.3/lib
- analysis directory: /home/yano/work/e559/art
- working directory: /home/yano/work/e559/art
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

- `artenv make`

```
$ artenv make
Enter the path to root> /home/yano/local/root/v6.32.04
Enter the path to yaml-cpp> /home/yano/local/yaml-cpp/v0.8.0
Enter the path to the source of artemis> /home/yano/src/artemis/develop
Enter the path to build directory> /home/yano/build/artemis/artdev
Enter the install prefix> /home/yano/local/artemis/artdev
Artemis will be built and installed to your environment with the following settings.
- root: /home/yano/local/root/v6.32.04
- yaml-cpp: /home/yano/local/yaml-cpp/v0.8.0
- artemis:
  - source directory: /home/yano/src/artemis/develop
  - build directory: /home/yano/build/artemis/artdev
  - install prefix: /home/yano/local/artemis/artdev
OK? (y/N)>y
```

## License
Copyright (c) 2024 Takayuki YANO

The source code is licensed under the MIT License, see LICENSE.
