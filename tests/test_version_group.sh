#!/usr/bin/env bash
# Tests for: artenv version group dispatcher (v2.1 phase 1)

# bare `artenv version` prints the current version (ART_VERSION), exit 1 if unset
test_vg_bare_unset() {
  unset ART_VERSION
  run version
  assert_status "${status}" 1
  assert_contains "${output}" "ART_VERSION is not set"
}

test_vg_bare_set() {
  export ART_VERSION=v1
  run version
  unset ART_VERSION
  assert_status "${status}" 0
  [[ "${output}" == "v1" ]] || fail "expected 'v1', got '${output}'"
}

# `version current` matches bare `version` (output and exit)
test_vg_current_matches_bare_set() {
  export ART_VERSION=v1
  run version
  local bare_out="${output}" bare_st="${status}"
  run version current
  unset ART_VERSION
  assert_status "${status}" "${bare_st}"
  [[ "${output}" == "${bare_out}" ]] || fail "current != bare: '${output}' vs '${bare_out}'"
}

test_vg_current_matches_bare_unset() {
  unset ART_VERSION
  run version
  local bare_out="${output}" bare_st="${status}"
  run version current
  assert_status "${status}" "${bare_st}"
  [[ "${output}" == "${bare_out}" ]] || fail "current != bare: '${output}' vs '${bare_out}'"
}

# `version ls` matches the `versions` shim
test_vg_ls_matches_versions_shim() {
  fake_native_version foo
  fake_native_version bar
  run version ls
  local ls_out="${output}" ls_st="${status}"
  run versions
  assert_status "${status}" "${ls_st}"
  [[ "${output}" == "${ls_out}" ]] || fail "version ls != versions: '${output}' vs '${ls_out}'"
}

# group help: -h / --help / help all print usage with exit 0
test_vg_help_dash_h() {
  run version -h
  assert_status "${status}" 0
  assert_contains "${output}" "usage: artenv version"
}

test_vg_help_long() {
  run version --help
  assert_status "${status}" 0
  assert_contains "${output}" "usage: artenv version"
}

test_vg_help_word() {
  run version help
  assert_status "${status}" 0
  assert_contains "${output}" "usage: artenv version"
}

# unknown subcommand dies with exit 1
test_vg_unknown_action() {
  run version bogus
  assert_status "${status}" 1
  assert_contains "${output}" "no such version subcommand"
}

# an unknown option (leading dash) is rejected
test_vg_unknown_option() {
  run version --bogus
  assert_status "${status}" 1
  assert_contains "${output}" "unknown option"
}
