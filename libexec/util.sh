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

set_archived_flag() {
  # Set or clear the `archived` flag in a single-table TOML file.
  # yq v4 cannot write TOML tables, so this is a text operation that
  # preserves every other field (uri/digest/git_repos/binds/...).
  local conf="$1"
  local value="$2"
  require_file "${conf}"

  local dir tmp
  dir="$(dirname -- "${conf}")"
  tmp="$(mktemp "${dir}/.tmp.archived.XXXXXX")"

  # Drop any existing archived line; the table header is always kept.
  grep -v '^archived[[:space:]]*=' -- "${conf}" > "${tmp}" || true

  if [[ "${value}" == "true" ]]; then
    printf 'archived = true\n' >> "${tmp}"
  fi

  mv -- "${tmp}" "${conf}"
}

# --- templates -------------------------------------------------------------
# Templates live under ${ARTENV_ROOT}/templates/<namespace>/<template>/, where
# <namespace> is either a template repo (cloned from template-repos/<name>.toml)
# or the reserved name `local' for user-managed templates. `local' is never
# cloned, updated, or removed by artenv.

# Reject template path components that could escape the templates tree.
validate_template_component() {
  local comp="$1"
  [[ -n "${comp}" ]]                              || die "invalid template name: (empty)"
  [[ "${comp}" != *"/"* ]]                        || die "invalid template name: ${comp}"
  [[ "${comp}" != "." && "${comp}" != ".." ]]     || die "invalid template name: ${comp}"
  return 0
}

# Print configured template repo names (one per line, sorted).
list_template_repos() {
  local repos_dir="${ARTENV_ROOT}/template-repos"
  [[ -d "${repos_dir}" ]] || return 0
  local -a files=()
  shopt -s nullglob
  files=("${repos_dir}"/*.toml)
  shopt -u nullglob
  local f
  for f in "${files[@]}"; do
    basename "${f}" .toml
  done | sort
}

# Print "true" or "false" for a repo's enabled flag (default true).
# Note: toml_get cannot be used here because its `//' fallback treats the
# boolean `false' like a missing key, collapsing `enabled = false' to true.
template_repo_enabled_flag() {
  local conf="${ARTENV_ROOT}/template-repos/$1.toml"
  local val="true"
  if [[ -f "${conf}" ]]; then
    val="$(yq -p toml -oy -r '.repo.enabled' "${conf}")"
  fi
  if [[ "${val}" == "false" ]]; then
    printf 'false\n'
  else
    printf 'true\n'
  fi
}

# Return 0 if the repo is enabled (default) or has no config; 1 if disabled.
template_repo_enabled() {
  [[ "$(template_repo_enabled_flag "$1")" == "true" ]]
}

# Print usable templates as "<namespace>/<template>", sorted. Includes local/*
# unconditionally and <repo>/* for enabled repos only.
list_templates() {
  local base="${ARTENV_ROOT}/templates"
  [[ -d "${base}" ]] || return 0
  local -a ns_dirs=()
  shopt -s nullglob
  ns_dirs=("${base}"/*/)
  shopt -u nullglob

  local ns_path ns tmpl_path tmpl
  for ns_path in "${ns_dirs[@]}"; do
    ns="$(basename "${ns_path}")"
    if [[ "${ns}" != "local" ]]; then
      template_repo_enabled "${ns}" || continue
    fi
    local -a tmpls=()
    shopt -s nullglob
    tmpls=("${ns_path}"*/)
    shopt -u nullglob
    for tmpl_path in "${tmpls[@]}"; do
      tmpl="$(basename "${tmpl_path}")"
      printf '%s/%s\n' "${ns}" "${tmpl}"
    done
  done | sort
}

# Resolve "[<repo>/]<name>" to an absolute template directory. On success sets
# the RESOLVED_TEMPLATE_PATH global and returns 0; otherwise dies.
# shellcheck disable=SC2034  # RESOLVED_TEMPLATE_PATH is consumed by the caller
resolve_template() {
  local spec="$1"
  local base="${ARTENV_ROOT}/templates"

  if [[ "${spec}" == */* ]]; then
    local repo="${spec%%/*}"
    local name="${spec#*/}"
    validate_template_component "${repo}"
    validate_template_component "${name}"
    local path="${base}/${repo}/${name}"
    [[ -d "${path}" ]] || die "template not found: ${spec}"
    RESOLVED_TEMPLATE_PATH="${path}"
    return 0
  fi

  validate_template_component "${spec}"
  local -a matches=()
  local t
  while IFS= read -r t; do
    [[ "${t##*/}" == "${spec}" ]] && matches+=("${t}")
  done < <(list_templates)

  case "${#matches[@]}" in
    0) die "template not found: ${spec}" ;;
    1) RESOLVED_TEMPLATE_PATH="${base}/${matches[0]}"; return 0 ;;
    *)
      { printf 'artenv: ambiguous template: %s\n' "${spec}"
        printf 'candidates:\n'
        printf '  %s\n' "${matches[@]}"
      } >&2
      exit 1
      ;;
  esac
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
