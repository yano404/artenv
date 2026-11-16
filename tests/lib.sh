#!/usr/bin/env bash
# shellcheck disable=SC2034  # output/status are globals consumed by the sourcing test files
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
  # Silence deprecation notices by default so shim/canonical output stays
  # byte-identical; the deprecation tests opt back in by unsetting this.
  export ARTENV_NO_DEPRECATION=1
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

fake_artlogin_template() {
  mkdir -p "${ARTENV_ROOT}/libexec"
  printf '#seed\n' > "${ARTENV_ROOT}/libexec/artlogin.sh"
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
# Mirrors util.sh's toml_get: the plain `//` fallback would collapse an
# explicit `false` (or `null`) to the default, so branch on key presence
# instead of relying on jq/yq truthiness.
toml_field() { # <file> <section> <key>
  local file="$1" section="$2" key="$3"
  local out present value
  out="$(yq -p toml -oy -r "((.${section} // {}) | has(\"${key}\")), (.${section}.${key})" "${file}")"
  present="${out%%$'\n'*}"
  value="${out#*$'\n'}"
  if [[ "${present}" == "true" ]]; then
    printf '%s\n' "${value}"
  else
    printf '%s\n' ""
  fi
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

# Install a vendored yq under $ARTENV_ROOT/vendor/bin/yq by copying the real
# system yq (run.sh gates on a system yq being present). Used to exercise the
# "vendored takes priority over system" resolution path offline.
fake_vendored_yq() {
  mkdir -p "${ARTENV_ROOT}/vendor/bin"
  cp -- "$(command -v yq)" "${ARTENV_ROOT}/vendor/bin/yq"
  chmod +x "${ARTENV_ROOT}/vendor/bin/yq"
}

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

# Abort the current test immediately. Each test runs in its own subshell (see
# run.sh), so `exit 1` fails just that test, not the whole runner. `exit`
# (rather than `return 1`) is deliberate: a `return` only fails the test when
# the failing assertion happens to be the test's last statement, so a passing
# assertion afterwards would otherwise mask a real failure.
fail() { printf 'ASSERT FAILED: %s\n' "$*" >&2; exit 1; }

assert_status()       { [[ "${1}" -eq "${2}" ]] || fail "expected exit ${2}, got ${1} ${3:-}"; }
assert_contains()     { [[ "${1}" == *"${2}"* ]] || fail "expected output to contain '${2}'; got: ${1}"; }
assert_not_contains() { [[ "${1}" != *"${2}"* ]] || fail "expected output NOT to contain '${2}'; got: ${1}"; }
assert_file()         { [[ -f "${1}" ]] || fail "expected file to exist: ${1}"; }
assert_no_file()      { [[ ! -e "${1}" ]] || fail "expected file to be gone: ${1}"; }

# --- image-repo / fake ghcr fixtures -----------------------------------------

# Write the tracked image-repo seed into the sandbox (the sandbox has no share/).
seed_share_image_default() {
  mkdir -p "${ARTENV_ROOT}/share/image-repos"
  cp -- "${ARTENV_REPO}/share/image-repos/default.toml" \
    "${ARTENV_ROOT}/share/image-repos/default.toml"
}

# Register a fake public image: fake_ghcr_image <image> <tag>[=<digest>]...
# The default digest of a tag is sha256:<tag>. No tags = an image with an
# empty tag list.
fake_ghcr_image() {
  local image="$1"; shift
  local path="${image#ghcr.io/}" spec
  local dir="${ARTENV_ROOT}/.fake-ghcr/${path//\//__}"
  mkdir -p "${dir}"
  : > "${dir}/tags"
  for spec in "$@"; do
    if [[ "${spec}" == *=* ]]; then
      printf '%s %s\n' "${spec%%=*}" "${spec#*=}" >> "${dir}/tags"
    else
      printf '%s sha256:%s\n' "${spec}" "${spec}" >> "${dir}/tags"
    fi
  done
}

# Put a fake `curl` on PATH. It serves the anonymous token, tags/list JSON and
# `-I` manifest headers for registered images; anything else exits 22.
use_fake_ghcr() {
  mkdir -p "${ARTENV_ROOT}/.fake-bin"
  cat > "${ARTENV_ROOT}/.fake-bin/curl" <<'EOS'
#!/usr/bin/env bash
url="" head=0
for a in "$@"; do
  case "${a}" in
    -I) head=1 ;;
    https://*) url="${a}" ;;
  esac
done
root="${ARTENV_ROOT}/.fake-ghcr"
dirof() { printf '%s/%s' "${root}" "${1//\//__}"; }
case "${url}" in
  https://ghcr.io/token\?scope=repository:*)
    p="${url#*repository:}"; p="${p%%:pull*}"
    [[ -d "$(dirof "${p}")" ]] || exit 22
    printf '{"token":"faketoken"}\n' ;;
  https://ghcr.io/v2/*/tags/list)
    p="${url#https://ghcr.io/v2/}"; p="${p%/tags/list}"
    [[ -d "$(dirof "${p}")" ]] || exit 22
    list=""
    while read -r t d; do list+="\"${t}\","; done < "$(dirof "${p}")/tags"
    printf '{"name":"%s","tags":[%s]}\n' "${p}" "${list%,}" ;;
  https://ghcr.io/v2/*/manifests/*)
    p="${url#https://ghcr.io/v2/}"; tag="${p##*/manifests/}"; p="${p%/manifests/*}"
    [[ -d "$(dirof "${p}")" ]] || exit 22
    d="$(awk -v t="${tag}" '$1==t{print $2}' "$(dirof "${p}")/tags")"
    [[ -n "${d}" ]] || exit 22
    printf 'HTTP/2 200\r\ndocker-content-digest: %s\r\n\r\n' "${d}" ;;
  *) exit 22 ;;
esac
EOS
  chmod +x "${ARTENV_ROOT}/.fake-bin/curl"
  export PATH="${ARTENV_ROOT}/.fake-bin:${PATH}"
}
