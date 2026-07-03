#!/usr/bin/env bash
# shellcheck disable=SC2154  # status/output are set by run()/run_in() in lib.sh
# Tests for: old command names are pure exec shims to their canonical targets.
# Because each shim is a bare `exec`, the old and new forms must produce
# byte-for-byte identical stdout/stderr and the same exit status.

# _equiv <stdin> <old-cmdline> <new-cmdline>
# cmdlines are space-separated argument strings (no embedded spaces needed here).
_equiv() {
  local stdin="$1" old_line="$2" new_line="$3"
  local o_out o_st n_out n_st
  # shellcheck disable=SC2086
  run_in "${stdin}" ${old_line}
  o_out="${output}"; o_st="${status}"
  # shellcheck disable=SC2086
  run_in "${stdin}" ${new_line}
  n_out="${output}"; n_st="${status}"

  [[ "${o_st}" -eq "${n_st}" ]] || \
    fail "exit mismatch: [${old_line}]=${o_st} vs [${new_line}]=${n_st}"
  [[ "${o_out}" == "${n_out}" ]] || \
    fail "output mismatch [${old_line}] vs [${new_line}]:
--- ${old_line} ---
${o_out}
--- ${new_line} ---
${n_out}"
}

# --- version group shims ----------------------------------------------------

test_shim_versions_ls() {
  fake_native_version foo
  fake_native_version bar
  _equiv "" "versions" "version ls"
}

test_shim_versions_ls_all() {
  fake_native_version foo
  run archive-version foo   # archive so -a has an effect
  _equiv "" "versions -a" "version ls -a"
}

test_shim_register_version_usage() {
  _equiv "" "register-version" "version register"
}

test_shim_register_version_interactive() {
  fake_native_version foo
  # Reaches the interactive `select` then hits EOF; both paths behave identically.
  _equiv "" "register-version newv" "version register newv"
}

test_shim_remove_version() {
  fake_native_version foo
  _equiv "" "remove-version nope -y" "version remove nope -y"
}

test_shim_archive_version() {
  fake_native_version foo
  _equiv "" "archive-version nope" "version archive nope"
}

test_shim_unarchive_version() {
  fake_native_version foo
  _equiv "" "unarchive-version nope" "version unarchive nope"
}

test_shim_install_help() {
  _equiv "" "install -h" "version install -h"
}

# --- env bare-name shims ----------------------------------------------------

test_shim_register_env_usage() {
  _equiv "" "register-env" "register"
}

test_shim_register_env_interactive() {
  fake_native_version foo
  _equiv "" "register-env newe" "register newe"
}

test_shim_remove_env() {
  make_env e1 foo
  _equiv "" "remove-env nope -y" "remove nope -y"
}

test_shim_archive_env() {
  make_env e1 foo
  _equiv "" "archive-env nope" "archive nope"
}

test_shim_unarchive_env() {
  make_env e1 foo
  _equiv "" "unarchive-env nope" "unarchive nope"
}
