#!/bin/bash

if [[ -z "${1:-}" ]]; then
    echo "usage: artlogin username"
    return 1
fi

proj_dir=$ART_ANALYSIS_DIR
git_repos=$ART_REPOS

username=$1
userdir=$proj_dir/user/$username

# If user directory exist, cd user directory.
if [[ -d "${userdir}" ]]; then
    cd "${userdir}" || return 1
    export ART_WORK_DIR=$userdir
    return 0
elif [[ -e "${userdir}" ]]; then
    echo "error: file $userdir exist."
    return 1
fi

# If user directory does not exist, create user directory and clone repos.
echo "user '$1' not found."

while true; do
    echo -n "create new user? (y/n): "
    read -r answer
    case $answer in
        y)
            break
            ;;
        n)
            echo "cancelled."
            return 0
            ;;
    esac
done

git clone "${git_repos}" "${userdir}"
cd "${userdir}" || return 1
git submodule init
git submodule update

while true; do
    echo -n "input fullname: "
    read -r fullname
    echo -n "OK? (y/n): "
    read -r answer
    case $answer in
        y)
            break
            ;;
    esac
done

git config user.name "$fullname"

while true; do
    echo -n "input email address: "
    read -r email
    echo -n "OK? (y/n): "
    read -r answer
    case $answer in
        y)
            break
            ;;
    esac
done

git config user.email "$email"

export ART_WORK_DIR=$userdir

return 0

