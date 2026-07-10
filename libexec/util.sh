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

# --- yq resolution & wrapper -----------------------------------------------
# artenv needs mikefarah/yq v4+ for its TOML support (`-p toml`). The unrelated
# PyPI package `yq` (kislyuk's jq wrapper) installs the same command name but
# cannot parse TOML, so a bare `yq` on PATH is not trustworthy. We resolve an
# absolute path to a suitable binary into ARTENV_YQ and route every call through
# the yq() wrapper below.
#
# Deliberately NOT a PATH prepend: artenv-sh-shell's activate_native re-exports
# PATH into the user's login shell, so putting vendor/bin on PATH would leak our
# vendored yq into the user's environment and shadow theirs. The wrapper keeps
# the vendored binary confined to artenv's own subprocesses. ARTENV_YQ is never
# exported, so it does not leak either.

# Route all yq calls through the resolved absolute path. `command` + an absolute
# path avoids re-entering this function (no recursion). :? makes an unresolved
# ARTENV_YQ a hard error rather than silently running a stray PATH yq; callers
# must resolve first via require_yq/resolve_yq.
yq() {
  command "${ARTENV_YQ:?ARTENV_YQ is not resolved; call require_yq first}" "$@"
}

# Return 0 iff <path> is a mikefarah yq of major version >= 4. The PyPI yq
# prints a different `--version` banner (no "mikefarah") and is rejected.
yq_is_mikefarah_v4() {
  local bin="$1" out token major
  out="$("${bin}" --version 2>/dev/null)" || return 1
  [[ "${out}" == *mikefarah* ]] || return 1
  token="${out##* }"      # trailing token, e.g. "v4.47.1"
  token="${token#v}"      # -> "4.47.1"
  major="${token%%.*}"    # -> "4"
  [[ "${major}" =~ ^[0-9]+$ ]] || return 1
  [[ "${major}" -ge 4 ]]
}

# Resolve an absolute path to a usable yq into ARTENV_YQ. Idempotent and cheap
# (this runs on the hot path via require_yq): once ARTENV_YQ is set it returns
# immediately; otherwise it does at most a stat plus one `--version`. Order:
#   1. $ARTENV_ROOT/vendor/bin/yq (our pinned vendored binary) if executable.
#   2. a system yq on PATH, but only when it is mikefarah v4+.
# Returns 0 with ARTENV_YQ set, or 1 if no usable yq was found.
resolve_yq() {
  [[ -n "${ARTENV_YQ:-}" ]] && return 0

  local vendored="${ARTENV_ROOT:-}/vendor/bin/yq"
  if [[ -n "${ARTENV_ROOT:-}" && -x "${vendored}" ]]; then
    ARTENV_YQ="${vendored}"
    return 0
  fi

  # type -P searches PATH for an external executable, ignoring the yq() function.
  local sys
  sys="$(type -P yq 2>/dev/null || true)"
  if [[ -n "${sys}" ]] && yq_is_mikefarah_v4 "${sys}"; then
    ARTENV_YQ="${sys}"
    return 0
  fi

  return 1
}

require_yq() {
  resolve_yq && return 0

  # Miss: lazily vendor yq (F1 hybrid). Attempt an auto-bootstrap at most once
  # per process, and only when the download base looks reachable so an offline
  # compute node fails fast instead of waiting out a download timeout. On a
  # reachable network bootstrap_yq installs and sets ARTENV_YQ (or dies with a
  # network-aware message); we then re-resolve.
  if [[ -z "${_ARTENV_YQ_BOOTSTRAP_TRIED:-}" && "${ARTENV_NO_AUTO_BOOTSTRAP:-}" != "1" ]]; then
    _ARTENV_YQ_BOOTSTRAP_TRIED=1
    if yq_net_reachable; then
      bootstrap_yq ""   # explicit empty force: install only if missing
      resolve_yq && return 0
    fi
  fi

  die "yq (mikefarah v4+) is required. On a login node with network access run 'artenv bootstrap' to vendor a pinned yq, or manually place a yq binary at ${ARTENV_ROOT:-\$ARTENV_ROOT}/vendor/bin/yq"
}

# --- yq vendoring (bootstrap) ----------------------------------------------
# Fetch a pinned, statically-linked mikefarah/yq (a Go binary, glibc-independent
# -> portable across HPC nodes) and install it under $ARTENV_ROOT/vendor/bin/yq.
# Bump the version and the matching per-arch SHA-256 pins together.
ARTENV_YQ_VERSION="v4.47.1"

# Overridable seams. ARTENV_YQ_BASE_URL lets a mirror (or the offline test
# harness) redirect the download; the SHA-256 pins are likewise env-overridable
# so the test harness can verify a locally-staged asset; the timeouts bound
# curl/wget so a fetch can never hang.
: "${ARTENV_YQ_SHA256_amd64:=0fb28c6680193c41b364193d0c0fc4a03177aecde51cfc04d506b1517158c2fb}"
: "${ARTENV_YQ_SHA256_arm64:=b7f7c991abe262b0c6f96bbcb362f8b35429cefd59c8b4c2daa4811f1e9df599}"
: "${ARTENV_YQ_BASE_URL:=https://github.com/mikefarah/yq/releases/download}"
: "${ARTENV_YQ_CONNECT_TIMEOUT:=10}"
: "${ARTENV_YQ_MAX_TIME:=120}"

# Map `uname -m` to mikefarah's asset arch suffix, or die on an unsupported one.
yq_asset_arch() {
  local machine
  machine="$(uname -m)"
  case "${machine}" in
    x86_64|amd64)  printf 'amd64\n' ;;
    aarch64|arm64) printf 'arm64\n' ;;
    *) die "unsupported architecture for vendored yq: ${machine} (install yq manually to ${ARTENV_ROOT:-\$ARTENV_ROOT}/vendor/bin/yq)" ;;
  esac
}

# Return 0 if the download base looks reachable, without ever hanging. A local
# mirror (file:// or an absolute path) is always "reachable". For http(s) it
# issues a strictly time-bounded HEAD; any HTTP response (even a 404) proves
# reachability, so `-f` is intentionally omitted here.
yq_net_reachable() {
  local base="${ARTENV_YQ_BASE_URL%/}/"
  case "${base}" in
    file://*|/*) return 0 ;;
  esac
  if command -v curl >/dev/null 2>&1; then
    if curl -sS -I --connect-timeout "${ARTENV_YQ_CONNECT_TIMEOUT}" \
         --max-time "${ARTENV_YQ_MAX_TIME}" -o /dev/null "${base}" 2>/dev/null; then
      return 0
    fi
    return 1
  fi
  if command -v wget >/dev/null 2>&1; then
    if wget -q --spider "--connect-timeout=${ARTENV_YQ_CONNECT_TIMEOUT}" \
         "--timeout=${ARTENV_YQ_MAX_TIME}" "${base}" 2>/dev/null; then
      return 0
    fi
    return 1
  fi
  return 1
}

# Download <url> to <out> without ever blocking on a prompt or hanging. Local
# mirrors (file:// or an absolute path) are copied directly for CI portability
# (curl's file:// support varies); http(s) uses curl then wget, both bounded by
# connect + total timeouts. Returns non-zero on failure.
yq_download() {
  local url="$1" out="$2"

  case "${url}" in
    file://*) cp -- "${url#file://}" "${out}"; return ;;
    /*)       cp -- "${url}" "${out}";         return ;;
  esac

  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --connect-timeout "${ARTENV_YQ_CONNECT_TIMEOUT}" \
      --max-time "${ARTENV_YQ_MAX_TIME}" -o "${out}" "${url}"
    return
  fi
  if command -v wget >/dev/null 2>&1; then
    wget -q "--connect-timeout=${ARTENV_YQ_CONNECT_TIMEOUT}" \
      "--timeout=${ARTENV_YQ_MAX_TIME}" -O "${out}" "${url}"
    return
  fi
  die "neither curl nor wget is available to fetch yq"
}

# Fetch, checksum-verify, and atomically install the pinned yq into
# $ARTENV_ROOT/vendor/bin/yq. With <force>="force" it re-fetches even if a
# vendored binary already exists. On success sets ARTENV_YQ to the installed
# path and returns 0; on any failure it removes the temp file and dies.
# The temp file is created inside the destination dir so the final `mv` is an
# atomic same-filesystem rename (safe for concurrent login nodes on a shared FS).
bootstrap_yq() {
  local force="${1:-}"

  [[ -n "${ARTENV_ROOT:-}" ]] || die "ARTENV_ROOT is not set"

  local dest_dir="${ARTENV_ROOT}/vendor/bin"
  local dest="${dest_dir}/yq"

  if [[ "${force}" != "force" && -x "${dest}" ]]; then
    ARTENV_YQ="${dest}"
    return 0
  fi

  local arch
  arch="$(yq_asset_arch)"   # dies on an unsupported architecture

  local sha_var="ARTENV_YQ_SHA256_${arch}"
  local expected="${!sha_var:-}"
  [[ -n "${expected}" ]] || die "no pinned SHA-256 for arch: ${arch}"

  if ! command -v sha256sum >/dev/null 2>&1; then
    die "sha256sum is required to verify the vendored yq"
  fi

  mkdir -p -- "${dest_dir}" || die "failed to create ${dest_dir}"

  local url="${ARTENV_YQ_BASE_URL%/}/${ARTENV_YQ_VERSION}/yq_linux_${arch}"

  local tmp
  tmp="$(mktemp "${dest_dir}/.yq.XXXXXX")" || die "failed to create a temp file in ${dest_dir}"

  if ! yq_download "${url}" "${tmp}"; then
    rm -f -- "${tmp}"
    die "failed to fetch yq from ${url} (run 'artenv bootstrap' on a login node with network access, or place a yq binary at ${dest})"
  fi

  local actual
  actual="$(sha256sum -- "${tmp}" | { read -r sum _rest; printf '%s' "${sum}"; })"
  if [[ "${actual}" != "${expected}" ]]; then
    rm -f -- "${tmp}"
    die "yq checksum mismatch for ${ARTENV_YQ_VERSION} yq_linux_${arch} (expected ${expected}, got ${actual}); refusing to install"
  fi

  if ! chmod +x -- "${tmp}"; then
    rm -f -- "${tmp}"
    die "failed to make ${tmp} executable"
  fi
  if ! mv -f -- "${tmp}" "${dest}"; then
    rm -f -- "${tmp}"
    die "failed to install yq to ${dest}"
  fi

  ARTENV_YQ="${dest}"
  return 0
}

toml_get() {
  local file="$1"
  local section="$2"
  local key="$3"
  local default="${4:-}"
  # Distinguish an explicit value (including the boolean `false') from a
  # missing key. yq/jq's `//' fallback treats `false'/`null' as absent, which
  # would collapse `key = false' to the default. Branch on presence instead:
  # emit "<present>\n<value>" in one call, then pick value or default.
  local out present value
  out="$(yq -p toml -oy -r "((.${section} // {}) | has(\"${key}\")), (.${section}.${key})" "${file}")"
  present="${out%%$'\n'*}"
  value="${out#*$'\n'}"
  if [[ "${present}" == "true" ]]; then
    printf '%s\n' "${value}"
  else
    printf '%s\n' "${default}"
  fi
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

# Seed the bundled default template repo on first use. Best-effort and
# zombie-free: only acts when the template-repos dir is ABSENT, so a user who
# deletes default.toml (leaving other repo confs) keeps it deleted. The tracked
# seed lives under share/; a missing seed (sandbox / non-repo install) is a
# clean no-op. Never returns non-zero (callers run under `set -e`).
ensure_default_repo() {
  local repos_dir="${ARTENV_ROOT}/template-repos"
  local seed="${ARTENV_ROOT}/share/template-repos/default.toml"
  [[ -d "${repos_dir}" ]] && return 0     # user territory — never touch
  [[ -f "${seed}" ]]      || return 0     # no seed present — no-op
  mkdir -p -- "${repos_dir}" 2>/dev/null || return 0
  cp -- "${seed}" "${repos_dir}/default.toml" 2>/dev/null || return 0
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

# Print "true" or "false" for a repo's enabled flag (default true; only an
# explicit `enabled = false' disables). toml_get now preserves boolean false,
# so it reads the flag correctly.
template_repo_enabled_flag() {
  local conf="${ARTENV_ROOT}/template-repos/$1.toml"
  local val="true"
  [[ -f "${conf}" ]] && val="$(toml_get "${conf}" repo enabled true)"
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

# Print a one-line hint to stderr when at least one enabled template repo has
# not been fetched yet, so `artenv templates update' would populate the cache.
templates_update_hint() {
  local name
  while IFS= read -r name; do
    template_repo_enabled "${name}" || continue
    [[ -d "${ARTENV_ROOT}/templates/${name}" ]] && continue
    printf "artenv: no templates cached; run 'artenv templates update' to fetch them\n" >&2
    return 0
  done < <(list_template_repos)
  return 0
}

# Report a missing template, adding the update hint when it may help.
die_template_not_found() {
  printf 'artenv: template not found: %s\n' "$1" >&2
  templates_update_hint
  exit 1
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
    [[ -d "${path}" ]] || die_template_not_found "${spec}"
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
    0) die_template_not_found "${spec}" ;;
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

# --- multi-user project skeleton -------------------------------------------
# Helpers for `artenv new --multiuser`: create an empty, group-shared analysis
# directory and seed a shared upstream bare git repository from a template.

# Return 0 if <dest> looks like a remote destination (URL or scp-like
# user@host:path), else 1. Used to reject remote repos in the local-only MVP.
dest_is_remote() {
  local dest="$1"
  case "${dest}" in
    *://*) return 0 ;;
    *@*:*) return 0 ;;
    *)     return 1 ;;
  esac
}

# Ensure <dir> exists and is writable by probing with a temp subdirectory.
# <label> is used to phrase the error message.
require_writable_dir() {
  local dir="$1"
  local label="$2"
  [[ -d "${dir}" ]] || die "${label} not found: ${dir}"
  local probe
  if ! probe=$(mktemp -d "${dir}/.artenv-probe.XXXXXX" 2>/dev/null); then
    die "${label} is not writable: ${dir}"
  fi
  rmdir -- "${probe}"
}

# Return 0 if <repo> is cloneable and has a `main` branch, else 1.
repo_has_main() {
  local repo="$1"
  git ls-remote --heads -- "${repo}" 2>/dev/null | grep -q 'refs/heads/main'
}

# Create <dir> as an empty, group-shared directory (mode 2770: group rwx +
# setgid, no world access). If <dir> already exists it must be an empty
# directory. Never removes anything; the caller owns cleanup.
create_shared_dir() {
  local dir="$1"
  if [[ -e "${dir}" ]]; then
    [[ -d "${dir}" ]] || die "${dir} is not a directory"
    if [[ -n "$(ls -A -- "${dir}" 2>/dev/null)" ]]; then
      die "shared directory is not empty: ${dir}"
    fi
  else
    mkdir -- "${dir}" || die "failed to create shared directory: ${dir}"
  fi
  if ! chmod 2770 -- "${dir}"; then
    die "failed to set group-shared permissions on: ${dir}"
  fi
}

# Seed a shared upstream bare repository at <repo> from the template directory
# <template_path>, committing on branch `main` with a message referencing the
# template label <rel>. The bare repo is created with --shared=group so group
# members can push. On any failure the self-created temp working repo and the
# bare repo are removed before dying; the caller owns removal of the enclosing
# shared directory.
bootstrap_shared_repo() {
  local template_path="$1"
  local repo="$2"
  local rel="$3"

  if [[ -e "${template_path}/.git" ]]; then
    die "template must not contain a .git entry: ${template_path}"
  fi

  local parent
  parent="$(dirname -- "${repo}")"
  require_writable_dir "${parent}" "repository parent directory"

  if [[ -e "${repo}" ]]; then
    [[ -d "${repo}" ]] || die "repository destination is not empty: ${repo}"
    if [[ -n "$(ls -A -- "${repo}" 2>/dev/null)" ]]; then
      die "repository destination is not empty: ${repo}"
    fi
  fi

  # -b main so the bare's HEAD is deterministic (independent of the host's
  # init.defaultBranch); otherwise `git clone` checks out the wrong/absent
  # default branch and yields an empty working tree.
  if ! git init -q --bare --shared=group -b main -- "${repo}"; then
    die "failed to create bare repository: ${repo}"
  fi

  # Seed via a throwaway working repo. A git identity is set explicitly so the
  # commit succeeds in a hermetic environment (CI) with no global git config.
  local tmp
  tmp="$(mktemp -d)"
  _bsr_fail() { rm -rf -- "${tmp}" "${repo}"; }

  if ! git init -q -b main -- "${tmp}"; then
    _bsr_fail; die "failed to initialize temporary repository"
  fi
  if ! git -C "${tmp}" config user.name "artenv"; then
    _bsr_fail; die "failed to configure temporary repository"
  fi
  if ! git -C "${tmp}" config user.email "artenv@localhost"; then
    _bsr_fail; die "failed to configure temporary repository"
  fi
  if ! cp -rT -- "${template_path}" "${tmp}"; then
    _bsr_fail; die "failed to copy template into temporary repository"
  fi
  if ! git -C "${tmp}" add -A; then
    _bsr_fail; die "failed to stage template files"
  fi
  if ! git -C "${tmp}" commit -q -m "Seed from template ${rel}"; then
    _bsr_fail; die "failed to commit template files (is the template empty?)"
  fi
  if ! git -C "${tmp}" push -q -- "${repo}" main; then
    _bsr_fail; die "failed to push seed commit to: ${repo}"
  fi

  if ! repo_has_main "${repo}"; then
    rm -rf -- "${tmp}" "${repo}"
    die "seeded repository is not cloneable (no main branch): ${repo}"
  fi

  rm -rf -- "${tmp}"
  return 0
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
