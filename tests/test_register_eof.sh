#!/usr/bin/env bash
# shellcheck disable=SC2154  # status/output are set by run()/run_in() in lib.sh
# Tests that the interactive register commands abort cleanly on stdin EOF
# (non-interactive invocation / Ctrl-D) instead of crashing with
# `tmp_conf: unbound variable`, and never leave a temp file behind.

test_register_eof_version_select() {
  # EOF at the `select version type` prompt.
  run_in "" version register newname
  assert_status "${status}" 1
  assert_contains "${output}" "aborted"
  assert_not_contains "${output}" "unbound variable"
}

test_register_eof_version_read() {
  # Select native (1), then EOF at the first path `read` (this is the path that
  # used to crash via the out-of-scope EXIT trap).
  run_in $'1\n' version register newname
  assert_status "${status}" 1
  assert_contains "${output}" "aborted"
  assert_not_contains "${output}" "unbound variable"
}

test_register_eof_version_apptainer_read() {
  # Select apptainer (2), then EOF at the image `read`. Must never crash.
  # The clean "aborted" message is only reachable when apptainer is installed
  # (otherwise the command dies earlier with "apptainer command not found",
  # which is still a clean exit) — so only assert it when apptainer exists.
  run_in $'2\n' version register newname
  assert_status "${status}" 1
  assert_not_contains "${output}" "unbound variable"
  if command -v apptainer >/dev/null 2>&1; then
    assert_contains "${output}" "aborted"
  fi
}

test_register_eof_env_select() {
  fake_native_version v1
  run_in "" register newenv
  assert_status "${status}" 1
  assert_contains "${output}" "aborted"
  assert_not_contains "${output}" "unbound variable"
}

test_register_eof_env_read() {
  fake_native_version v1
  # Select v1, then EOF at the working-directory `read`.
  run_in $'1\n' register newenv
  assert_status "${status}" 1
  assert_contains "${output}" "aborted"
  assert_not_contains "${output}" "unbound variable"
}

test_register_eof_no_leftover_temp() {
  fake_native_version v1
  # Use the read-EOF paths (select a type/version first, then EOF) so a temp
  # file is actually created before the abort — this exercises the EXIT-trap
  # cleanup, not just the pre-mktemp select-EOF path.
  run_in $'1\n' version register newname
  run_in $'1\n' register newenv
  local leftovers
  leftovers="$(find "${ARTENV_ROOT}/versions" "${ARTENV_ROOT}/envs" -name '.tmp.*' 2>/dev/null)"
  [[ -z "${leftovers}" ]] || fail "leftover temp files after abort: ${leftovers}"
}

test_register_eof_shim_inheritance() {
  # Deprecated shims exec the canonical commands, so they abort cleanly too.
  fake_native_version v1
  run_in "" register-version newname
  assert_status "${status}" 1
  assert_contains "${output}" "aborted"
  run_in "" register-env newenv
  assert_status "${status}" 1
  assert_contains "${output}" "aborted"
}
