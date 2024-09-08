#!/bin/bash

function usage() {
cat <<EOF
usage : $1 dc_name
usage : $2 setting_name
EOF
}

if [ $1_ = _ ] ; then
    usage $0
    exit
fi

prm_dir="$PWD/prm/mwdc/$1/dt2dl"
cd $prm_dir
if [ -d $2 ] ; then
    echo ln -sf $2 current
    rm -f current
    ln -sf $2 current
else
    echo "$prm_dir/$2 not found."
fi
