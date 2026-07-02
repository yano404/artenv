#!/usr/bin/env bash
# Tests for: artenv remove-version

test_rmv_basic_native() {
  fake_native_version foo
  run remove-version foo -y
  assert_status "${status}" 0
  assert_contains "${output}" "foo was removed"
  assert_no_file "${ARTENV_ROOT}/versions/foo.toml"
}

test_rmv_referenced_blocks() {
  fake_native_version foo
  make_env e559 foo
  run remove-version foo -y
  assert_status "${status}" 1
  assert_contains "${output}" "used by"
  assert_contains "${output}" "- e559"
  assert_file "${ARTENV_ROOT}/versions/foo.toml"   # untouched
}

test_rmv_referenced_force() {
  fake_native_version foo
  make_env e559 foo
  run remove-version foo -y --force
  assert_status "${status}" 0
  assert_contains "${output}" "foo was removed"
  assert_no_file "${ARTENV_ROOT}/versions/foo.toml"
}

test_rmv_purge_managed_deletes_sif() {
  apptainer_version_managed foo
  run remove-version foo -y --purge
  assert_status "${status}" 0
  assert_contains "${output}" "removed image"
  assert_no_file "${ARTENV_ROOT}/images/foo.sif"
  assert_no_file "${ARTENV_ROOT}/versions/foo.toml"
}

test_rmv_purge_external_keeps_sif() {
  apptainer_version_external foo
  run remove-version foo -y --purge
  assert_status "${status}" 0
  assert_contains "${output}" "not removing image outside"
  assert_file "${EXTDIR}/foo.sif"                  # external SIF preserved
  assert_no_file "${ARTENV_ROOT}/versions/foo.toml"
}

test_rmv_no_purge_keeps_sif() {
  apptainer_version_managed foo
  run remove-version foo -y
  assert_status "${status}" 0
  assert_file "${ARTENV_ROOT}/images/foo.sif"      # SIF kept without --purge
  assert_no_file "${ARTENV_ROOT}/versions/foo.toml"
}

test_rmv_notfound() {
  run remove-version nope -y
  assert_status "${status}" 1
  assert_contains "${output}" "version not found"
}

test_rmv_confirm_no_aborts() {
  fake_native_version foo
  run_in $'n\n' remove-version foo
  assert_status "${status}" 0
  assert_contains "${output}" "aborted"
  assert_file "${ARTENV_ROOT}/versions/foo.toml"   # not removed
}

test_rmv_confirm_yes() {
  fake_native_version foo
  run_in $'y\n' remove-version foo
  assert_status "${status}" 0
  assert_contains "${output}" "foo was removed"
  assert_no_file "${ARTENV_ROOT}/versions/foo.toml"
}

test_rmv_select_no_name() {
  fake_native_version aaa
  fake_native_version bbb
  run_in $'1\n' remove-version -y            # picks first (aaa)
  assert_status "${status}" 0
  assert_contains "${output}" "aaa was removed"
  assert_no_file "${ARTENV_ROOT}/versions/aaa.toml"
  assert_file "${ARTENV_ROOT}/versions/bbb.toml"
}

test_rmv_unknown_option() {
  run remove-version --bogus -y
  assert_status "${status}" 1
  assert_contains "${output}" "unknown option"
}

test_rmv_active_warns() {
  fake_native_version foo
  export ART_VERSION=foo
  run remove-version foo -y
  unset ART_VERSION
  assert_status "${status}" 0
  assert_contains "${output}" "currently active"
  assert_no_file "${ARTENV_ROOT}/versions/foo.toml"
}
