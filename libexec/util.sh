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

require_yq() {
  command -v yq >/dev/null 2>&1 || die "yq is required (dnf install yq)"
}

toml_get() {
  local file="$1"
  local section="$2"
  local key="$3"
  local default="${4:-}"
  yq -p toml -oy -r ".${section}.${key} // \"${default}\"" "${file}"
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

validate_version_conf() {
  local conf="$1"
  require_yq
  require_file "${conf}"

  local version_type
  version_type="$(yq -p toml -oy -r '.version.type // "native"' "${conf}")"

  if [[ "${version_type}" == "apptainer" ]]; then
    local image
    image="$(yq -p toml -oy -r '.version.image' "${conf}")"
    [[ -n "${image}" ]] || die "version.image not found in ${conf}"
    [[ -f "${image}" ]] || die "image not found: ${image}"
  else
    local artsys rootsys yamllib yamlcmake
    artsys="$(yq -p toml -oy -r '.version.artsys' "${conf}")"
    rootsys="$(yq -p toml -oy -r '.version.rootsys' "${conf}")"
    yamllib="$(yq -p toml -oy -r '.version.yamllib' "${conf}")"
    yamlcmake="$(yq -p toml -oy -r '.version.yamlcmake' "${conf}")"

    [[ -n "${artsys}" ]]    || die "version.artsys not found in ${conf}"
    [[ -n "${rootsys}" ]]   || die "version.rootsys not found in ${conf}"
    [[ -n "${yamllib}" ]]   || die "version.yamllib not found in ${conf}"
    [[ -n "${yamlcmake}" ]] || die "version.yamlcmake not found in ${conf}"

    [[ -d "${artsys}" ]]    || die "directory not found: ${artsys}"
    [[ -d "${rootsys}" ]]   || die "directory not found: ${rootsys}"
    [[ -d "${yamllib}" ]]   || die "directory not found: ${yamllib}"
    [[ -d "${yamlcmake}" ]] || die "directory not found: ${yamlcmake}"
    [[ -f "${rootsys}/bin/root-config" ]] || die "root-config not found: ${rootsys}/bin/root-config"
  fi
}

validate_env_conf() {
  local conf="$1"
  require_yq
  require_file "${conf}"

  local version_name work_dir
  version_name="$(yq -p toml -oy -r '.env.version' "${conf}")"
  work_dir="$(yq -p toml -oy -r '.env.work' "${conf}")"

  [[ -n "${version_name}" ]] || die "env.version not found in ${conf}"
  [[ -n "${work_dir}" ]]     || die "env.work not found in ${conf}"
  [[ -d "${work_dir}" ]]     || die "work directory not found: ${work_dir}"

  local version_conf="${ARTENV_ROOT}/versions/${version_name}.toml"
  validate_version_conf "${version_conf}"
}

# shellcheck disable=SC2034
load_env_metadata() {
  local env_name="$1"
  local env_conf="${ARTENV_ROOT}/envs/${env_name}.toml"

  require_yq
  require_file "${env_conf}"

  ENV_VERSION_NAME="$(yq -p toml -oy -r '.env.version'           "${env_conf}")"
  ENV_WORK_DIR="$(yq -p toml -oy -r '.env.work'                  "${env_conf}")"
  ENV_GIT_REPOS="$(yq -p toml -oy -r '.env.git_repos // ""'      "${env_conf}")"
  ENV_BINDS="$(yq -p toml -oy -r '.env.binds // [] | join(",")' "${env_conf}")"

  [[ -n "${ENV_VERSION_NAME}" ]] || die "env.version not found in ${env_conf}"
  [[ -n "${ENV_WORK_DIR}" ]]     || die "env.work not found in ${env_conf}"

  local use_artlogin_raw
  use_artlogin_raw="$(yq -p toml -oy -r '.env.use_artlogin // "false"' "${env_conf}")"
  if [[ "${use_artlogin_raw}" == "true" ]]; then
    ENV_USE_ARTLOGIN="YES"
  else
    ENV_USE_ARTLOGIN="NO"
  fi

  local version_conf="${ARTENV_ROOT}/versions/${ENV_VERSION_NAME}.toml"
  require_file "${version_conf}"

  ENV_VERSION_TYPE="$(yq -p toml -oy -r '.version.type // "native"' "${version_conf}")"

  if [[ "${ENV_VERSION_TYPE}" == "apptainer" ]]; then
    ENV_APPTAINER_IMAGE="$(yq -p toml -oy -r '.version.image' "${version_conf}")"
    ENV_ARTSYS=""
    ENV_ROOTSYS=""
    ENV_YAMLLIB=""
    ENV_YAMLCMAKE=""
  else
    ENV_APPTAINER_IMAGE=""
    ENV_ARTSYS="$(yq -p toml -oy -r '.version.artsys'    "${version_conf}")"
    ENV_ROOTSYS="$(yq -p toml -oy -r '.version.rootsys'  "${version_conf}")"
    ENV_YAMLLIB="$(yq -p toml -oy -r '.version.yamllib'  "${version_conf}")"
    ENV_YAMLCMAKE="$(yq -p toml -oy -r '.version.yamlcmake' "${version_conf}")"
  fi

  if [[ "${ENV_USE_ARTLOGIN}" == "YES" ]]; then
    ENV_ARTLOGIN_SH="${ARTENV_ROOT}/envs/${env_name}.artlogin.sh"
  else
    ENV_ARTLOGIN_SH=""
  fi
}
