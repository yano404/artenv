#!/usr/bin/env bash
# shellcheck disable=SC2154  # status/output are set by run() in lib.sh
# Additional offline tests for yq resolution/vendoring (`libexec/util.sh`,
# `libexec/artenv-bootstrap`, `libexec/artenv-doctor`, `libexec/artenv-init`).
# These complement tests/test_yq_bootstrap.sh by covering gaps flagged during
# independent verification: an old-but-genuine mikefarah v3 system yq, the
# ARTENV_NO_AUTO_BOOTSTRAP override, wall-clock speed of the offline paths
# (not just exit code/message), a real retry-after-failure, the
# resolve-memoization guard (no repeated `--version` calls per process), the
# `artenv shell` no-leak invariant, and arm64 asset-name wiring.
#
# Completely offline: any network-shaped path points at either a local
# mirror directory (via file/absolute-path handling in yq_download) or an
# unreachable host with a 1s timeout, so nothing here ever touches the
# internet or blocks.

# --- helpers (mirrors tests/test_yq_bootstrap.sh) ---------------------------

_yq_test_arch() {
  case "$(uname -m)" in
    x86_64|amd64)  printf 'amd64' ;;
    aarch64|arm64) printf 'arm64' ;;
    *)             printf 'unknown' ;;
  esac
}

_yq_pinned_version() {
  bash -c 'source "'"${ARTENV_REPO}"'/libexec/util.sh"; printf "%s" "${ARTENV_YQ_VERSION}"'
}

# Stage the real system yq as <base>/<version>/yq_linux_<arch> and export the
# base URL plus the matching SHA-256 pin.
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

# Stage the mirror asset under an explicit <arch> label (used for the arm64
# wiring test), regardless of the host's real uname -m.
stage_yq_mirror_for_arch() {
  local arch="$1" ver sysyq mirror sha
  ver="$(_yq_pinned_version)"
  sysyq="$(command -v yq)"
  mirror="${SANDBOX}/mirror"
  mkdir -p "${mirror}/${ver}"
  cp -- "${sysyq}" "${mirror}/${ver}/yq_linux_${arch}"
  sha="$(sha256sum -- "${mirror}/${ver}/yq_linux_${arch}" | { read -r s _; printf '%s' "${s}"; })"
  export ARTENV_YQ_BASE_URL="${mirror}"
  export "ARTENV_YQ_SHA256_${arch}=${sha}"
}

# A fake PyPI-style yq (kislyuk's jq wrapper): answers --version without the
# "mikefarah" banner, so resolve_yq must reject it. Shadows any real yq.
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

# A genuine-banner mikefarah yq, but major version 3 (pre-TOML-support era).
# resolve_yq must reject it on the version check, not just the banner check.
stub_old_mikefarah_yq_on_path() {
  local d="${SANDBOX}/oldyqbin"
  mkdir -p "${d}"
  cat > "${d}/yq" <<'SH'
#!/usr/bin/env bash
if [[ "$1" == "--version" ]]; then
  echo "yq (https://github.com/mikefarah/yq/) version v3.4.3"
  exit 0
fi
exit 0
SH
  chmod +x "${d}/yq"
  export PATH="${d}:${PATH}"
}

# Remove yq entirely from PATH resolution, without losing every other tool in
# the same directory (on this machine /usr/bin holds both `yq` and coreutils
# like cat/rm/date/sha256sum, so simply dropping the whole directory from PATH
# would break the test harness itself). For any PATH entry that contains a
# `yq` executable, substitute a same-order sanitized mirror directory that
# symlinks every OTHER entry through; directories without a `yq` are kept as-is.
strip_yq_from_path() {
  local mirrors_root="${SANDBOX}/noyqbin"
  mkdir -p "${mirrors_root}"
  local -a newpath=()
  local IFS=':'
  local p i=0
  for p in ${PATH}; do
    if [[ -x "${p}/yq" ]]; then
      i=$((i + 1))
      local mirror="${mirrors_root}/${i}"
      mkdir -p "${mirror}"
      local f base
      for f in "${p}"/*; do
        [[ -e "${f}" ]] || continue
        base="$(basename -- "${f}")"
        [[ "${base}" == "yq" ]] && continue
        ln -sf -- "${f}" "${mirror}/${base}"
      done
      newpath+=("${mirror}")
    else
      newpath+=("${p}")
    fi
  done
  local joined
  joined="$(IFS=:; printf '%s' "${newpath[*]}")"
  export PATH="${joined}"
}

# Prepend a fake `uname` reporting an unsupported machine.
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

resolved_yq_path() {
  ( set +e
    unset ARTENV_YQ
    # shellcheck source=/dev/null
    source "${ARTENV_REPO}/libexec/util.sh"
    resolve_yq || exit 1
    printf '%s' "${ARTENV_YQ}"
  )
}

# Wall-clock elapsed seconds for a command (integer, floor). Used to prove an
# "offline dies fast" claim empirically rather than trusting the exit code
# alone -- a command that dies after waiting out a long default timeout would
# still pass a status-only assertion but is exactly the regression we care
# about here.
elapsed_seconds() { # <start_ns>
  local start="$1" end
  end="$(date +%s%N)"
  printf '%d' $(( (end - start) / 1000000000 ))
}

# --- 1. resolution order: reject an old (genuine banner) mikefarah v3 -------

test_yq_resolve_rejects_old_mikefarah_v3() {
  stub_old_mikefarah_yq_on_path
  if resolved_yq_path >/dev/null; then
    fail "resolve_yq accepted a mikefarah v3 (pre-v4) system yq"
  fi
}

# --- 2. die message wording: no root-assuming package-manager hint ----------

test_yq_require_yq_die_message_has_no_root_assumption() {
  strip_yq_from_path
  export ARTENV_YQ_BASE_URL="http://127.0.0.1:9/nope"
  export ARTENV_YQ_CONNECT_TIMEOUT=1
  export ARTENV_YQ_MAX_TIME=1

  fake_native_version v1
  make_env e1 v1 false
  run doctor e1
  assert_status "${status}" 1
  assert_contains "${output}" "artenv bootstrap"
  assert_contains "${output}" "vendor/bin/yq"
  assert_not_contains "${output}" "dnf install yq"
  assert_not_contains "${output}" "apt-get"
  assert_not_contains "${output}" "yum install"
}

# --- 3. ARTENV_NO_AUTO_BOOTSTRAP suppresses the F1 auto-vendor --------------

test_yq_no_auto_bootstrap_env_blocks_auto_vendor() {
  stage_yq_mirror >/dev/null   # reachable local mirror: would auto-vendor...
  stub_pypi_yq_on_path         # ...because no valid system yq resolves...
  export ARTENV_NO_AUTO_BOOTSTRAP=1   # ...but this must suppress it.

  fake_native_version v1
  make_env e1 v1 false
  run info e1
  assert_status "${status}" 1
  assert_contains "${output}" "artenv bootstrap"
  assert_no_file "${ARTENV_ROOT}/vendor/bin/yq"
}

# --- 4/5. offline paths must fail FAST, not hang out a long timeout --------

test_yq_bootstrap_offline_uncached_is_fast() {
  export ARTENV_YQ_BASE_URL="http://127.0.0.1:9/nope"
  export ARTENV_YQ_CONNECT_TIMEOUT=1
  export ARTENV_YQ_MAX_TIME=1

  local t0
  t0="$(date +%s%N)"
  run bootstrap
  local secs
  secs="$(elapsed_seconds "${t0}")"

  assert_status "${status}" 1
  [[ "${secs}" -le 5 ]] || fail "bootstrap took ${secs}s to fail offline; expected <=5s (possible hang)"
}

test_yq_require_yq_offline_is_fast() {
  strip_yq_from_path
  export ARTENV_YQ_BASE_URL="http://127.0.0.1:9/nope"
  export ARTENV_YQ_CONNECT_TIMEOUT=1
  export ARTENV_YQ_MAX_TIME=1

  fake_native_version v1
  make_env e1 v1 false

  local t0
  t0="$(date +%s%N)"
  run doctor e1
  local secs
  secs="$(elapsed_seconds "${t0}")"

  assert_status "${status}" 1
  [[ "${secs}" -le 5 ]] || fail "require_yq took ${secs}s to fail offline; expected <=5s (possible hang)"
}

# --- 6. a failed bootstrap never blocks a subsequent successful retry ------

test_yq_bootstrap_retry_after_mismatch_succeeds() {
  local dest arch
  dest="${ARTENV_ROOT}/vendor/bin/yq"
  # NOTE: call directly (not via `$(...)`) -- stage_yq_mirror's `export`s only
  # take effect in the current shell; capturing it via command substitution
  # forks a subshell and silently discards them (see the reported bug in
  # tests/test_yq_bootstrap.sh's own use of this exact pattern).
  stage_yq_mirror >/dev/null
  arch="$(_yq_test_arch)"
  local sha_var="ARTENV_YQ_SHA256_${arch}"
  local good_sha="${!sha_var}"

  export "${sha_var}=deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
  run bootstrap
  assert_status "${status}" 1
  assert_contains "${output}" "checksum mismatch"
  assert_no_file "${dest}"

  export "${sha_var}=${good_sha}"
  run bootstrap
  assert_status "${status}" 0
  assert_file "${dest}"
  [[ -x "${dest}" ]] || fail "yq installed on retry is not executable: ${dest}"
}

# --- 7. resolve is memoized within one process: no repeated `--version` ----

test_yq_resolve_no_repeated_version_calls() {
  local d="${SANDBOX}/countbin"
  local counter="${SANDBOX}/version_calls.log"
  mkdir -p "${d}"
  : > "${counter}"
  cat > "${d}/yq" <<SH
#!/usr/bin/env bash
if [[ "\$1" == "--version" ]]; then
  echo called >> "${counter}"
  echo "yq (https://github.com/mikefarah/yq/) version v4.47.1"
  exit 0
fi
exec "$(command -v yq)" "\$@"
SH
  chmod +x "${d}/yq"
  export PATH="${d}:${PATH}"

  # Use apptainer fixtures (real dummy .sif, real `apptainer` binary on this
  # host) so doctor reports a clean OK across all three envs; a native
  # fixture's placeholder /tmp/x/... paths don't exist on disk and would
  # make doctor legitimately report NG, which is an unrelated confound here --
  # this test only cares about the `--version` call count, not doctor health.
  apptainer_version_managed v1
  make_env e1 v1 false
  make_env e2 v1 false
  make_env e3 v1 false

  # `doctor --all` resolves yq once in main() and then again per-env via
  # load_env_metadata for e1, e2, e3 -- four require_yq call sites in one
  # process. Once ARTENV_YQ is set, resolve_yq's fast path must short-circuit
  # every later call without re-invoking `--version`. (Exit status is not
  # asserted here: doctor's overall pass/fail also depends on an `apptainer`
  # binary being on PATH, which is an unrelated confound for this test.)
  run doctor --all

  local calls
  calls="$(wc -l < "${counter}")"
  [[ "${calls}" -le 1 ]] || fail "expected at most 1 '--version' probe across doctor --all, got ${calls}"
}

# --- 8. `artenv shell` (native) never leaks ARTENV_YQ or the yq() wrapper --

test_yq_sh_shell_no_leak() {
  fake_native_version v1
  make_env e1 v1 false

  run sh-shell e1
  assert_status "${status}" 0
  assert_not_contains "${output}" "ARTENV_YQ"
  assert_not_contains "${output}" "yq()"
  assert_not_contains "${output}" "yq() {"
}

# --- 9. init: no network I/O even when the default env needs (failing)     #
#     yq resolution -- must fail fast, not hang on the unreachable mirror.  #

test_yq_init_default_env_is_offline_fast() {
  stub_pypi_yq_on_path   # no resolvable yq
  export ARTENV_YQ_BASE_URL="http://127.0.0.1:9/nope"
  export ARTENV_YQ_CONNECT_TIMEOUT=1
  export ARTENV_YQ_MAX_TIME=1

  fake_native_version v1
  make_env e1 v1 false
  set_default_env e1

  local t0
  t0="$(date +%s%N)"
  set +e
  "${ARTENV_BIN}" init - >"${SANDBOX}/init.out" 2>"${SANDBOX}/init.err"
  set -e
  local secs
  secs="$(elapsed_seconds "${t0}")"

  [[ "${secs}" -le 5 ]] || fail "init with a broken default env took ${secs}s; expected <=5s (possible network hang)"
  # Whatever the ultimate exit status (the default env's shell activation may
  # legitimately fail without a usable yq), the hint must already have fired
  # on stderr before any such failure, and stdout must stay eval-safe.
  assert_not_contains "$(< "${SANDBOX}/init.out")" "yq not found"
  local err
  err="$(< "${SANDBOX}/init.err")"
  assert_contains "${err}" "yq not found"
}

# --- 10. arm64 asset-name wiring (arch->asset->SHA plumbing), no real arm64 #
#     hardware required: label the real (amd64) system yq as the arm64      #
#     asset and drive the arm64 branch via a stubbed `uname -m`. This proves#
#     the plumbing end-to-end (arch detection -> URL -> SHA var lookup ->   #
#     verify -> install -> execute) without needing to execute foreign code.#

test_yq_bootstrap_arm64_wiring() {
  stage_yq_mirror_for_arch arm64
  local d="${SANDBOX}/unamebin"
  mkdir -p "${d}"
  cat > "${d}/uname" <<'SH'
#!/usr/bin/env bash
if [[ "$1" == "-m" ]]; then echo "aarch64"; exit 0; fi
exec /usr/bin/env uname "$@"
SH
  chmod +x "${d}/uname"
  export PATH="${d}:${PATH}"

  run bootstrap
  assert_status "${status}" 0
  assert_file "${ARTENV_ROOT}/vendor/bin/yq"
  [[ -x "${ARTENV_ROOT}/vendor/bin/yq" ]] || fail "arm64-labeled yq not executable"

  fake_native_version v1
  make_env e1 v1 false
  run info e1
  assert_status "${status}" 0
  assert_contains "${output}" "artemis version: v1"
}

# --- 11. doctor --orphans reports yq provenance (vendored vs system) -------

test_yq_doctor_orphans_reports_vendored() {
  fake_vendored_yq
  run doctor --orphans
  assert_status "${status}" 0
  assert_contains "${output}" "yq: vendored"
  assert_contains "${output}" "${ARTENV_ROOT}/vendor/bin/yq"
}

test_yq_doctor_orphans_reports_system() {
  run doctor --orphans
  assert_status "${status}" 0
  assert_contains "${output}" "yq: system"
}
