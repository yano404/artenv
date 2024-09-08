artenv
======

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
<env-name> was registered
```

## Commands

- `ls`               : Print the environment list
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

## License
Copyright (c) 2024 Takayuki YANO

The source code is licensed under the MIT License, see LICENSE.
