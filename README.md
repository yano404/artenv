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

```
mkdir $ARTENV_ROOT/versions/<version-name>
ln -s /path/to/artemis $ARTENV_ROOT/versions/<version-name>/artsys
ln -s /path/to/root $ARTENV_ROOT/versions/<version-name>/rootsys
```

Register analysis environment:

```
mkdir $ARTENV_ROOT/envs/<env-name>
ln -s $ARTENV_ROOT/versions/<version-you-use> $ARTENV_ROOT/envs/<env-name>/version
ln -s /path/to/analysis_directory $ARTENV_ROOT/envs/<env-name>/work
```

## License
Copyright (c) 2023 Takayuki YANO

The source code is licensed under the MIT License, see LICENSE.
