#!/usr/bin/env bash
# shellcheck disable=SC2154  # status/output are set by run() in lib.sh
# Tests for: yq resolution (ARTENV_YQ) and vendoring (`artenv bootstrap`).
#
# Completely offline. The download is redirected to a LOCAL mirror by pointing
# ARTENV_YQ_BASE_URL at a directory under $SANDBOX and staging the real system
# yq there as the "release asset", then pinning its freshly-computed SHA-256 via
# the ARTENV_YQ_SHA256_<arch> env override. bootstrap_yq's yq_download copies
# local/absolute-path URLs directly, so no network is ever touched; the
# installed binary is then executed to prove a real round-trip.

# --- helpers ---------------------------------------------------------------

# Map uname -m to mikefarah's asset arch suffix (mirrors util.sh:yq_asset_arch).
_yq_test_arch() {
  case "$(uname -m)" in
    x86_64|amd64)  printf 'amd64' ;;
    aarch64|arm64) printf 'arm64' ;;
    *)             printf 'unknown' ;;
  esac
}

# The version pinned in libexec/util.sh (read from source so tests survive a
# version bump).
_yq_pinned_version() {
  bash -c 'source "'"${ARTENV_REPO}"'/libexec/util.sh"; printf "%s" "${ARTENV_YQ_VERSION}"'
}

# Stage the real system yq as <base>/<version>/yq_linux_<arch> and export the
# base URL plus the matching SHA-256 pin. Echoes the destination that a
# successful bootstrap will produce.
stage_yq_mirror() {
  local arch ver sysyq mirror sha
  arch="$(_yq_test_arch)"
  ver="$(_yq_pinned_version)"
  sysyq="$(command -v yq)"
  mirror="${SANDBOX}/mirror"
  mkdir -p "${mirror}/${ver}"
  cp -- "${sysyq}" "${mirror}/${ver}/yq_linux_${arch}"
  sha="$(sha256sum -- "${mirror}/${ver}/yq_linux_${arch}" | { read -r s _; printf '%s' "${s}"; })"
  export ARTENV_YQ_BASE_URL="${mirror}"
  export "ARTENV_YQ_SHA256_${arch}=${sha}"
  printf '%s' "${ARTENV_ROOT}/vendor/bin/yq"
}

# Prepend a fake PyPI-style yq (kislyuk's jq wrapper) to PATH: it answers
# `--version` with a banner that lacks "mikefarah", so resolve_yq must reject
# it. Any usable system yq is thereby shadowed (type -P returns this one first).
stub_pypi_yq_on_path() {
  local d="${SANDBOX}/pypibin"
  mkdir -p "${d}"
  cat > "${d}/yq" <<'SH'
#!/usr/bin/env bash
if [[ "$1" == "--version" ]]; then
  echo "yq 3.4.3"
  exit 0
fi
exit 0
SH
  chmod +x "${d}/yq"
  export PATH="${d}:${PATH}"
}

# Prepend a fake `uname` reporting an unsupported machine, so yq_asset_arch dies.
stub_bad_uname_on_path() {
  local d="${SANDBOX}/unamebin"
  mkdir -p "${d}"
  cat > "${d}/uname" <<'SH'
#!/usr/bin/env bash
if [[ "$1" == "-m" ]]; then echo "sparc64"; exit 0; fi
exec /usr/bin/env uname "$@"
SH
  chmod +x "${d}/uname"
  export PATH="${d}:${PATH}"
}

# Resolve yq in a subshell (via util.sh) and print the resolved ARTENV_YQ.
# Exits non-zero when nothing resolves. Inherits ARTENV_ROOT/PATH from the test.
resolved_yq_path() {
  ( set +e
    unset ARTENV_YQ
    # shellcheck source=/dev/null
    source "${ARTENV_REPO}/libexec/util.sh"
    resolve_yq || exit 1
    printf '%s' "${ARTENV_YQ}"
  )
}

# --- resolution order ------------------------------------------------------

# 1. Vendored binary wins over a system yq.
test_yq_resolve_vendored_beats_system() {
  fake_vendored_yq
  local got
  got="$(resolved_yq_path)" || fail "resolve_yq found nothing with a vendored yq present"
  [[ "${got}" == "${ARTENV_ROOT}/vendor/bin/yq" ]] \
    || fail "expected vendored yq, got '${got}'"
}

# 2. System yq is accepted when it is mikefarah v4+ (the runner's yq).
test_yq_resolve_system_when_mikefarah_v4() {
  local sys got
  sys="$(command -v yq)"
  got="$(resolved_yq_path)" || fail "resolve_yq rejected a valid system yq"
  [[ "${got}" == "${sys}" ]] || fail "expected system yq '${sys}', got '${got}'"
}

# 3. A PyPI-style yq (no "mikefarah" banner) is rejected; nothing resolves.
test_yq_resolve_rejects_pypi_yq() {
  stub_pypi_yq_on_path
  if resolved_yq_path >/dev/null; then
    fail "resolve_yq accepted a PyPI (non-mikefarah) yq"
  fi
}

# --- bootstrap: fetch / verify / install -----------------------------------

# 4. Happy path: fetch -> verify -> atomic install, then a real round-trip
#    (the installed binary parses TOML through the normal command surface).
test_yq_bootstrap_happy_path() {
  local dest
  dest="$(stage_yq_mirror)"

  run bootstrap
  assert_status "${status}" 0
  assert_contains "${output}" "vendored yq"
  assert_file "${dest}"
  [[ -x "${dest}" ]] || fail "installed yq is not executable: ${dest}"

  # No stray temp files left in the destination dir.
  local -a leftovers=("${ARTENV_ROOT}/vendor/bin/".yq.*)
  if [[ -e "${leftovers[0]}" ]]; then fail "temp file left behind: ${leftovers[*]}"; fi

  # Round-trip: resolve now prefers the vendored binary; info reads TOML.
  fake_native_version v1
  make_env e1 v1 false
  run info e1
  assert_status "${status}" 0
  assert_contains "${output}" "artemis version: v1"
}

# 5. Idempotent: a second bootstrap (no --force) is a clean no-op success.
test_yq_bootstrap_idempotent() {
  local dest
  dest="$(stage_yq_mirror)"

  run bootstrap
  assert_status "${status}" 0
  run bootstrap
  assert_status "${status}" 0
  assert_file "${dest}"
}

# 6. Checksum mismatch: temp is discarded and nothing is installed.
test_yq_bootstrap_sha_mismatch_dies() {
  local dest arch
  dest="$(stage_yq_mirror)"
  arch="$(_yq_test_arch)"
  export "ARTENV_YQ_SHA256_${arch}=deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef"

  run bootstrap
  assert_status "${status}" 1
  assert_contains "${output}" "checksum mismatch"
  assert_no_file "${dest}"
  local -a leftovers=("${ARTENV_ROOT}/vendor/bin/".yq.*)
  if [[ -e "${leftovers[0]}" ]]; then fail "temp file left behind after mismatch: ${leftovers[*]}"; fi
  return 0
}

# 7. Unsupported architecture: dies naming the arch (base is a reachable local
#    mirror, so the failure is the arch check, not a network preflight).
test_yq_bootstrap_unsupported_arch_dies() {
  stage_yq_mirror >/dev/null
  stub_bad_uname_on_path

  run bootstrap
  assert_status "${status}" 1
  assert_contains "${output}" "unsupported architecture"
  assert_contains "${output}" "sparc64"
}

# --- offline / timeout behavior --------------------------------------------

# 8. Offline + nothing cached: `artenv bootstrap` fails fast with guidance and
#    never hangs (unreachable host + minimal timeouts; port 9 refuses at once).
test_yq_bootstrap_offline_uncached_dies() {
  export ARTENV_YQ_BASE_URL="http://127.0.0.1:9/nope"
  export ARTENV_YQ_CONNECT_TIMEOUT=1
  export ARTENV_YQ_MAX_TIME=1

  run bootstrap
  assert_status "${status}" 1
  assert_contains "${output}" "artenv bootstrap"
  assert_no_file "${ARTENV_ROOT}/vendor/bin/yq"
}

# 9. Auto-trigger offline: with only a PyPI yq resolvable and no network, a
#    command that needs yq dies fast with the require_yq guidance (does not use
#    the rejected yq, does not hang).
test_yq_require_yq_offline_guidance() {
  stub_pypi_yq_on_path
  export ARTENV_YQ_BASE_URL="http://127.0.0.1:9/nope"
  export ARTENV_YQ_CONNECT_TIMEOUT=1
  export ARTENV_YQ_MAX_TIME=1

  fake_native_version v1
  make_env e1 v1 false
  run doctor e1
  assert_status "${status}" 1
  assert_contains "${output}" "artenv bootstrap"
}

# 10. Auto-vendor on miss: no system yq resolvable, but the (local) mirror is
#     reachable, so a yq-needing command self-heals by vendoring, then succeeds.
test_yq_auto_vendor_on_miss() {
  # Stage the mirror from the REAL system yq first, then shadow it: order
  # matters because stage_yq_mirror copies `command -v yq`.
  stage_yq_mirror >/dev/null    # local mirror is "reachable" -> auto-bootstrap
  stub_pypi_yq_on_path          # shadow the real system yq -> resolve miss

  fake_native_version v1
  make_env e1 v1 false
  run info e1
  assert_status "${status}" 0
  assert_contains "${output}" "artemis version: v1"
  assert_file "${ARTENV_ROOT}/vendor/bin/yq"
}

# --- flag surface (parity with `artenv upgrade`) ---------------------------

test_yq_bootstrap_help() {
  run bootstrap -h
  assert_status "${status}" 0
  assert_contains "${output}" "usage: artenv bootstrap"
  assert_contains "${output}" "--help"

  run bootstrap --help
  assert_status "${status}" 0
  assert_contains "${output}" "usage: artenv bootstrap"
}

test_yq_bootstrap_unknown_option() {
  run bootstrap --bogus
  assert_status "${status}" 1
  assert_contains "${output}" "unknown option: --bogus"
}

test_yq_bootstrap_unexpected_argument() {
  run bootstrap foo
  assert_status "${status}" 1
  assert_contains "${output}" "unexpected argument: foo"
  assert_contains "${output}" "usage: artenv bootstrap"
}

# --- init hint (stderr only, no network) -----------------------------------

# The init hint fires only when no yq resolves; assert it is stderr-only there
# and absent when a vendored yq is present. run() merges streams, so we drive
# the binary directly to separate stdout from stderr.
test_yq_init_hint_when_missing() {
  stub_pypi_yq_on_path   # no resolvable yq
  local out err
  out="$("${ARTENV_BIN}" init - 2>"${SANDBOX}/ihint.err")"
  err="$(< "${SANDBOX}/ihint.err")"
  assert_contains "${out}" "artenv() {"          # function still emitted on stdout
  assert_not_contains "${out}" "yq not found"    # hint must not pollute stdout
  assert_contains "${err}" "run 'artenv bootstrap'"
}

test_yq_init_no_hint_when_vendored() {
  fake_vendored_yq
  local err
  "${ARTENV_BIN}" init - >/dev/null 2>"${SANDBOX}/ihint2.err"
  err="$(< "${SANDBOX}/ihint2.err")"
  assert_not_contains "${err}" "yq not found"
}
