#!/usr/bin/env bash
# Test helpers for artenv (plain bash, no external framework required).
# Every test runs against an isolated ARTENV_ROOT sandbox; the real
# ~/.artenv is never touched.

ARTENV_BIN="${ARTENV_REPO}/bin/artenv"

# --- sandbox lifecycle ------------------------------------------------------

setup_sandbox() {
  SANDBOX="$(mktemp -d)"
  export ARTENV_ROOT="${SANDBOX}"
  mkdir -p "${ARTENV_ROOT}/versions" "${ARTENV_ROOT}/envs" "${ARTENV_ROOT}/images"
  # Do not inherit the developer's active shell state.
  unset ART_VERSION ART_PROJECT
  EXTDIR=""
}

teardown_sandbox() {
  [[ -n "${SANDBOX:-}"  && -d "${SANDBOX}" ]] && rm -rf "${SANDBOX}"
  [[ -n "${EXTDIR:-}"   && -d "${EXTDIR}"  ]] && rm -rf "${EXTDIR}"
  SANDBOX="" ; EXTDIR=""
}

# --- fixtures ---------------------------------------------------------------

fake_native_version() { # <name>
  cat > "${ARTENV_ROOT}/versions/$1.toml" <<EOF
[version]
type = "native"
artsys = "/tmp/x/artemis"
rootsys = "/tmp/x/root"
yamllib = "/tmp/x/yaml/lib"
yamlcmake = "/tmp/x/yaml/cmake"
EOF
}

apptainer_version_managed() { # <name>  (SIF placed under images/)
  touch "${ARTENV_ROOT}/images/$1.sif"
  cat > "${ARTENV_ROOT}/versions/$1.toml" <<EOF
[version]
type = "apptainer"
image = "${ARTENV_ROOT}/images/$1.sif"
EOF
}

apptainer_version_external() { # <name>  (SIF placed outside ARTENV_ROOT)
  EXTDIR="${EXTDIR:-$(mktemp -d)}"
  touch "${EXTDIR}/$1.sif"
  cat > "${ARTENV_ROOT}/versions/$1.toml" <<EOF
[version]
type = "apptainer"
image = "${EXTDIR}/$1.sif"
EOF
}

apptainer_version_full() { # <name>  (apptainer version carrying uri + digest)
  touch "${ARTENV_ROOT}/images/$1.sif"
  cat > "${ARTENV_ROOT}/versions/$1.toml" <<EOF
[version]
type = "apptainer"
uri = "docker://example.org/artemis:$1"
image = "${ARTENV_ROOT}/images/$1.sif"
digest = "sha256:deadbeef"
EOF
}

make_rich_env() { # <name> <version>  (env carrying git_repos, binds, use_artlogin)
  cat > "${ARTENV_ROOT}/envs/$1.toml" <<EOF
[env]
version = "$2"
work = "/tmp"
git_repos = "/tmp/repos/$1"
binds = ["/data:/data", "/scratch"]
use_artlogin = true
EOF
  touch "${ARTENV_ROOT}/envs/$1.artlogin.sh"
  return 0
}

# Read a scalar field straight from a TOML file (test-side, via yq).
toml_field() { # <file> <section> <key>
  yq -p toml -oy -r ".$2.$3 // \"\"" "$1"
}

make_env() { # <name> <version> [artlogin:true|false]
  local artlogin="${3:-false}"
  cat > "${ARTENV_ROOT}/envs/$1.toml" <<EOF
[env]
version = "$2"
work = "/tmp"
use_artlogin = ${artlogin}
EOF
  [[ "${artlogin}" == "true" ]] && touch "${ARTENV_ROOT}/envs/$1.artlogin.sh"
  return 0
}

set_default_env() { printf '%s\n' "$1" > "${ARTENV_ROOT}/env"; }

# --- run artenv, capturing $output (stdout+stderr) and $status --------------

run() { # <args...>
  set +e
  output="$("${ARTENV_BIN}" "$@" 2>&1)"
  status=$?
  set -e
}

run_in() { # <stdin_string> <args...>
  local input="$1"; shift
  set +e
  output="$(printf '%s' "${input}" | "${ARTENV_BIN}" "$@" 2>&1)"
  status=$?
  set -e
}

# --- assertions -------------------------------------------------------------

fail() { printf 'ASSERT FAILED: %s\n' "$*" >&2; return 1; }

assert_status()       { [[ "${1}" -eq "${2}" ]] || fail "expected exit ${2}, got ${1} ${3:-}"; }
assert_contains()     { [[ "${1}" == *"${2}"* ]] || fail "expected output to contain '${2}'; got: ${1}"; }
assert_not_contains() { [[ "${1}" != *"${2}"* ]] || fail "expected output NOT to contain '${2}'; got: ${1}"; }
assert_file()         { [[ -f "${1}" ]] || fail "expected file to exist: ${1}"; }
assert_no_file()      { [[ ! -e "${1}" ]] || fail "expected file to be gone: ${1}"; }
