#!/usr/bin/env bash

remove_path () {
    echo `echo -n $1 | awk -v RS=: -v ORS=: '$0 != "'$2'"' | sed 's/:$//'`;
}

prepend_path () {
    if [ -z $1 ]
    then
        echo $2
    else
        echo $2:$1
    fi
}

append_path () {
    if [ -z $1 ]
    then
        echo $2
    else
        echo $1:$2
    fi
}
