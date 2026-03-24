#!/usr/bin/env bash

die() {
  printf 'artenv: %s\n' "$*" >&2
  exit 1
}

require_exists() {
  local path="$1"
  [[ -e "${path}" || -L "${path}" ]] || die "path not found: ${path}"
}

require_dir() {
  local path="$1"
  [[ -d "${path}" ]] || die "directory not found: ${path}"
}

require_file() {
  local path="$1"
  [[ -f "${path}" ]] || die "file not found: ${path}"
}

ensure_dir() {
  local path="$1"
  mkdir -p -- "${path}"
}

resolve_path() {
  local path="$1"

  if command -v realpath >/dev/null 2>&1; then
    realpath -- "${path}"
    return
  fi

  if command -v readlink >/dev/null 2>&1; then
    readlink -f -- "${path}"
    return
  fi

  die "realpath or readlink -f is required"
}

read_git_repos() {
  local path="$1"

  if [[ -f "${path}" && ! -L "${path}" ]]; then
    tr -d '\n' < "${path}"
    return 0
  fi

  if [[ -L "${path}" ]]; then
    readlink -- "${path}"
    return 0
  fi

  return 1
}

remove_path() {
  local path_list="${1-}"
  local target="${2-}"
  local -a items=()
  local -a out=()
  local item
  local joined=""

  IFS=':' read -r -a items <<< "${path_list}"

  for item in "${items[@]}"; do
    [[ -z "${item}" ]] && continue
    [[ "${item}" == "${target}" ]] && continue
    out+=("${item}")
  done

  for item in "${out[@]}"; do
    if [[ -z "${joined}" ]]; then
      joined="${item}"
    else
      joined="${joined}:${item}"
    fi
  done

  printf '%s\n' "${joined}"
}

prepend_path() {
  local path_list="${1-}"
  local target="${2-}"

  [[ -z "${target}" ]] && {
    printf '%s\n' "${path_list}"
    return
  }

  path_list="$(remove_path "${path_list}" "${target}")"

  if [[ -z "${path_list}" ]]; then
    printf '%s\n' "${target}"
  else
    printf '%s:%s\n' "${target}" "${path_list}"
  fi
}

append_path() {
  local path_list="${1-}"
  local target="${2-}"

  [[ -z "${target}" ]] && {
    printf '%s\n' "${path_list}"
    return
  }

  path_list="$(remove_path "${path_list}" "${target}")"

  if [[ -z "${path_list}" ]]; then
    printf '%s\n' "${target}"
  else
    printf '%s:%s\n' "${path_list}" "${target}"
  fi
}

validate_version_dir() {
  local version_dir="$1"

  require_dir "${version_dir}"
  require_exists "${version_dir}/artsys"
  require_exists "${version_dir}/rootsys"
  require_exists "${version_dir}/yamllib"
  require_exists "${version_dir}/yamlcmake"

  require_dir "$(resolve_path "${version_dir}/artsys")"
  require_dir "$(resolve_path "${version_dir}/rootsys")"
  require_dir "$(resolve_path "${version_dir}/yamllib")"
  require_dir "$(resolve_path "${version_dir}/yamlcmake")"
  require_file "$(resolve_path "${version_dir}/rootsys")/bin/root-config"
}

validate_env_dir() {
  local env_dir="$1"
  local version_dir
  local work_dir

  require_dir "${env_dir}"
  require_exists "${env_dir}/version"
  require_exists "${env_dir}/work"

  version_dir="$(resolve_path "${env_dir}/version")"
  work_dir="$(resolve_path "${env_dir}/work")"

  validate_version_dir "${version_dir}"
  require_dir "${work_dir}"

  if [[ -e "${env_dir}/artlogin.sh" ]]; then
    require_file "${env_dir}/artlogin.sh"
  fi
}

# shellcheck disable=SC2034
load_env_metadata() {
  local env_dir="$1"

  validate_env_dir "${env_dir}"

  local version_dir
  version_dir="$(resolve_path "${env_dir}/version")"

  ENV_VERSION_DIR="${version_dir}"
  ENV_VERSION_NAME="$(basename "${version_dir}")"
  ENV_ARTSYS="$(resolve_path "${version_dir}/artsys")"
  ENV_ROOTSYS="$(resolve_path "${version_dir}/rootsys")"
  ENV_YAMLLIB="$(resolve_path "${version_dir}/yamllib")"
  ENV_YAMLCMAKE="$(resolve_path "${version_dir}/yamlcmake")"
  ENV_WORK_DIR="$(resolve_path "${env_dir}/work")"

  ENV_GIT_REPOS=""
  if ENV_GIT_REPOS="$(read_git_repos "${env_dir}/git_repos" 2>/dev/null)"; then
    :
  else
    ENV_GIT_REPOS=""
  fi

  if [[ -f "${env_dir}/artlogin.sh" ]]; then
    ENV_USE_ARTLOGIN="YES"
  else
    ENV_USE_ARTLOGIN="NO"
  fi
}
