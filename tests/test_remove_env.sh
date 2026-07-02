#!/usr/bin/env bash
# Tests for: artenv remove-env

test_rme_basic() {
  make_env e559 foo
  run remove-env e559 -y
  assert_status "${status}" 0
  assert_contains "${output}" "e559 was removed"
  assert_no_file "${ARTENV_ROOT}/envs/e559.toml"
}

test_rme_artlogin_sidecar_removed() {
  make_env e559 foo true
  assert_file "${ARTENV_ROOT}/envs/e559.artlogin.sh"   # precondition
  run remove-env e559 -y
  assert_status "${status}" 0
  assert_no_file "${ARTENV_ROOT}/envs/e559.artlogin.sh"
  assert_no_file "${ARTENV_ROOT}/envs/e559.toml"
}

test_rme_default_blocks() {
  make_env e559 foo
  set_default_env e559
  run remove-env e559 -y
  assert_status "${status}" 1
  assert_contains "${output}" "default environment"
  assert_file "${ARTENV_ROOT}/envs/e559.toml"          # untouched
  assert_file "${ARTENV_ROOT}/env"                      # default pointer kept
}

test_rme_default_force_clears() {
  make_env e559 foo
  set_default_env e559
  run remove-env e559 -y --force
  assert_status "${status}" 0
  assert_contains "${output}" "default environment cleared"
  assert_contains "${output}" "e559 was removed"
  assert_no_file "${ARTENV_ROOT}/envs/e559.toml"
  assert_no_file "${ARTENV_ROOT}/env"                   # pointer cleared
}

test_rme_notfound() {
  run remove-env nope -y
  assert_status "${status}" 1
  assert_contains "${output}" "environment not found"
}

test_rme_confirm_no_aborts() {
  make_env e559 foo
  run_in $'n\n' remove-env e559
  assert_status "${status}" 0
  assert_contains "${output}" "aborted"
  assert_file "${ARTENV_ROOT}/envs/e559.toml"          # not removed
}

test_rme_select_no_name() {
  make_env aaa foo
  make_env bbb foo
  run_in $'1\n' remove-env -y                          # picks first (aaa)
  assert_status "${status}" 0
  assert_contains "${output}" "aaa was removed"
  assert_no_file "${ARTENV_ROOT}/envs/aaa.toml"
  assert_file "${ARTENV_ROOT}/envs/bbb.toml"
}

test_rme_active_warns() {
  make_env e559 foo
  export ART_PROJECT=e559
  run remove-env e559 -y
  unset ART_PROJECT
  assert_status "${status}" 0
  assert_contains "${output}" "currently active"
  assert_no_file "${ARTENV_ROOT}/envs/e559.toml"
}

test_rme_unknown_option() {
  run remove-env --bogus -y
  assert_status "${status}" 1
  assert_contains "${output}" "unknown option"
}

# Cross-cutting: the dispatcher must expose the new subcommands.
test_commands_lists_remove() {
  run commands
  assert_status "${status}" 0
  assert_contains "${output}" "remove-version"
  assert_contains "${output}" "remove-env"
}
