#!/usr/bin/env bash
# shellcheck disable=SC2154  # status/output are set by run()/run_in() in lib.sh
# Regression tests for non-interactive `artenv register` flags:
# --version/--work/--repos/--multiuser/--singleuser. Every invocation here
# goes through run()/run_in(), which always run non-tty, so these exercise
# the flag-or-die (non-tty) resolution path directly. The interactive tty
# prompt path is out of scope (needs a pty) and is left byte-identical by
# design; see test_register_eof.sh for its EOF-abort coverage.

# --- fully-flagged happy paths ----------------------------------------------

test_register_flags_singleuser_full() {
  fake_native_version v1
  run register e1 --version v1 --work "${ARTENV_ROOT}" --singleuser
  assert_status "${status}" 0
  assert_contains "${output}" "e1 was registered"

  local conf="${ARTENV_ROOT}/envs/e1.toml"
  assert_file "${conf}"
  [[ "$(toml_field "${conf}" env version)" == "v1" ]] || fail "expected version v1"
  local expected_work
  expected_work="$(realpath -- "${ARTENV_ROOT}")"
  [[ "$(toml_field "${conf}" env work)" == "${expected_work}" ]] || fail "expected resolved work dir"
  [[ "$(toml_field "${conf}" env use_artlogin)" == "false" ]] || fail "expected use_artlogin=false"
  [[ "$(toml_field "${conf}" env git_repos)" == "" ]] || fail "expected git_repos absent"
  assert_no_file "${ARTENV_ROOT}/envs/e1.artlogin.sh"
}

test_register_flags_multiuser_full() {
  fake_artlogin_template
  fake_native_version v1
  run register e2 --version v1 --work "${ARTENV_ROOT}" --multiuser --repos /tmp/repos/e2
  assert_status "${status}" 0
  assert_contains "${output}" "e2 was registered"

  local conf="${ARTENV_ROOT}/envs/e2.toml"
  assert_file "${conf}"
  [[ "$(toml_field "${conf}" env use_artlogin)" == "true" ]] || fail "expected use_artlogin=true"
  assert_file "${ARTENV_ROOT}/envs/e2.artlogin.sh"
  # Stored RAW: must NOT have been resolve_path'd into an absolute/real path
  # for a directory that doesn't exist (e.g. collapsed or canonicalized).
  [[ "$(toml_field "${conf}" env git_repos)" == "/tmp/repos/e2" ]] \
    || fail "expected git_repos stored verbatim as /tmp/repos/e2"
}

test_register_flags_repos_url_verbatim() {
  fake_artlogin_template
  fake_native_version v1
  run register e11 --version v1 --work "${ARTENV_ROOT}" --multiuser --repos https://example.com/x.git
  assert_status "${status}" 0
  local conf="${ARTENV_ROOT}/envs/e11.toml"
  [[ "$(toml_field "${conf}" env git_repos)" == "https://example.com/x.git" ]] \
    || fail "expected git_repos to stay a verbatim URL"
}

# --- multiuser without required --repos -------------------------------------

test_register_flags_multiuser_missing_repos() {
  fake_artlogin_template
  fake_native_version v1
  run register e3 --version v1 --work "${ARTENV_ROOT}" --multiuser
  assert_status "${status}" 1
  assert_contains "${output}" "git repos is required when artlogin is enabled"
  assert_no_file "${ARTENV_ROOT}/envs/e3.toml"
  local leftovers
  leftovers="$(find "${ARTENV_ROOT}/envs" -name '.tmp.*' 2>/dev/null)"
  [[ -z "${leftovers}" ]] || fail "leftover temp files after die: ${leftovers}"
}

# --- non-tty required-field dies --------------------------------------------

test_register_flags_missing_version_dies() {
  fake_native_version v1
  run register e4
  assert_status "${status}" 1
  assert_contains "${output}" "use --version"
}

test_register_flags_missing_work_dies() {
  fake_native_version v1
  run register e5 --version v1
  assert_status "${status}" 1
  assert_contains "${output}" "use --work"
}

# --- neither --multiuser nor --singleuser: defaults to single-user ---------

test_register_flags_default_singleuser_when_unspecified() {
  fake_native_version v1
  run register e6 --version v1 --work "${ARTENV_ROOT}"
  assert_status "${status}" 0
  local conf="${ARTENV_ROOT}/envs/e6.toml"
  assert_file "${conf}"
  [[ "$(toml_field "${conf}" env use_artlogin)" == "false" ]] || fail "expected default use_artlogin=false"
  assert_no_file "${ARTENV_ROOT}/envs/e6.artlogin.sh"
}

# --- --version validation ----------------------------------------------------

test_register_flags_version_not_found() {
  run register e7 --version nope --work "${ARTENV_ROOT}" --singleuser
  assert_status "${status}" 1
  assert_contains "${output}" "version not found"
  assert_no_file "${ARTENV_ROOT}/envs/e7.toml"
}

test_register_flags_version_archived() {
  fake_native_version v1
  run archive-version v1
  assert_status "${status}" 0
  run register e8 --version v1 --work "${ARTENV_ROOT}" --singleuser
  assert_status "${status}" 1
  assert_contains "${output}" "archived"
  assert_no_file "${ARTENV_ROOT}/envs/e8.toml"
}

# --- mutually exclusive flags ------------------------------------------------

test_register_flags_multiuser_singleuser_mutually_exclusive() {
  fake_native_version v1
  run register e9 --version v1 --work "${ARTENV_ROOT}" --multiuser --singleuser
  assert_status "${status}" 1
  assert_contains "${output}" "mutually exclusive"
  assert_no_file "${ARTENV_ROOT}/envs/e9.toml"
}

# --- help --------------------------------------------------------------------

test_register_flags_help_lists_flags() {
  run register -h
  assert_status "${status}" 0
  assert_contains "${output}" "--version"
  assert_contains "${output}" "--multiuser"

  run register --help
  assert_status "${status}" 0
  assert_contains "${output}" "--version"
  assert_contains "${output}" "--multiuser"
}

# --- deprecated shim forwards flags ------------------------------------------

test_register_flags_shim_forwards_flags() {
  fake_native_version v1
  run register-env e10 --version v1 --work "${ARTENV_ROOT}" --singleuser
  assert_status "${status}" 0
  local conf="${ARTENV_ROOT}/envs/e10.toml"
  assert_file "${conf}"
  [[ "$(toml_field "${conf}" env version)" == "v1" ]] || fail "expected version v1 via shim"
  [[ "$(toml_field "${conf}" env use_artlogin)" == "false" ]] || fail "expected use_artlogin=false via shim"
}
