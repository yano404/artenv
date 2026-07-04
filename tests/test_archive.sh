#!/usr/bin/env bash
# shellcheck disable=SC2154  # status/output are set by run()/run_in() in lib.sh
# Tests for: artenv archive-version / archive-env / unarchive-version / unarchive-env
# and the archived-aware behaviour of ls / versions / register-env.

# --- archive-version: sets flag, preserves other fields ---------------------

test_arcv_sets_flag_preserves_fields() {
  apptainer_version_full foo
  run archive-version foo
  assert_status "${status}" 0
  assert_contains "${output}" "foo was archived"

  local conf="${ARTENV_ROOT}/versions/foo.toml"
  local body; body="$(cat "${conf}")"
  assert_contains "${body}" "archived = true"
  # every other field must survive the rewrite
  assert_contains "${body}" 'type = "apptainer"'
  assert_contains "${body}" 'uri = "docker://example.org/artemis:foo"'
  assert_contains "${body}" 'image ='
  assert_contains "${body}" 'digest = "sha256:deadbeef"'
  [[ "$(toml_field "${conf}" version archived)" == "true" ]] || fail "archived not readable as true"
}

test_arcv_unarchive_clears_flag_preserves_fields() {
  apptainer_version_full foo
  run archive-version foo
  assert_status "${status}" 0
  run unarchive-version foo
  assert_status "${status}" 0
  assert_contains "${output}" "foo was unarchived"

  local conf="${ARTENV_ROOT}/versions/foo.toml"
  local body; body="$(cat "${conf}")"
  assert_not_contains "${body}" "archived"
  assert_contains "${body}" 'uri = "docker://example.org/artemis:foo"'
  assert_contains "${body}" 'digest = "sha256:deadbeef"'
  [[ "$(toml_field "${conf}" version archived)" == "" ]] || fail "archived should be absent"
}

test_arcv_double_archive_noop() {
  fake_native_version foo
  run archive-version foo
  assert_status "${status}" 0
  run archive-version foo
  assert_status "${status}" 0
  assert_contains "${output}" "already archived"
  # still exactly one archived line
  local n; n="$(grep -c '^archived' "${ARTENV_ROOT}/versions/foo.toml")"
  [[ "${n}" -eq 1 ]] || fail "expected 1 archived line, got ${n}"
}

test_arcv_unarchive_not_archived_noop() {
  fake_native_version foo
  run unarchive-version foo
  assert_status "${status}" 0
  assert_contains "${output}" "not archived"
}

test_arcv_notfound() {
  run archive-version nope
  assert_status "${status}" 1
  assert_contains "${output}" "version not found"
}

test_arcv_unknown_option() {
  run archive-version --bogus
  assert_status "${status}" 1
  assert_contains "${output}" "unknown option"
}

test_arcv_select_excludes_archived() {
  fake_native_version keep
  fake_native_version gone
  run archive-version gone
  assert_status "${status}" 0
  # no-name -> interactive select; feed EOF, inspect the menu contents
  run_in "" archive-version
  assert_contains "${output}" "keep"
  assert_not_contains "${output}" "gone"
}

# --- archive-env: sets flag, preserves other fields -------------------------

test_arce_sets_flag_preserves_fields() {
  fake_native_version foo
  make_rich_env e559 foo
  run archive-env e559
  assert_status "${status}" 0
  assert_contains "${output}" "e559 was archived"

  local conf="${ARTENV_ROOT}/envs/e559.toml"
  local body; body="$(cat "${conf}")"
  assert_contains "${body}" "archived = true"
  assert_contains "${body}" 'version = "foo"'
  assert_contains "${body}" 'git_repos = "/tmp/repos/e559"'
  assert_contains "${body}" 'binds ='
  assert_contains "${body}" 'use_artlogin = true'
  [[ "$(toml_field "${conf}" env archived)" == "true" ]] || fail "archived not readable as true"
  # array field survives intact
  [[ "$(yq -p toml -oy -r '.env.binds | join(",")' "${conf}")" == "/data:/data,/scratch" ]] \
    || fail "binds array not preserved"
}

test_arce_unarchive_clears_flag() {
  fake_native_version foo
  make_rich_env e559 foo
  run archive-env e559
  assert_status "${status}" 0
  run unarchive-env e559
  assert_status "${status}" 0
  assert_contains "${output}" "e559 was unarchived"
  local body; body="$(cat "${ARTENV_ROOT}/envs/e559.toml")"
  assert_not_contains "${body}" "archived"
  assert_contains "${body}" 'git_repos = "/tmp/repos/e559"'
}

test_arce_double_archive_noop() {
  make_env e559 foo
  run archive-env e559
  assert_status "${status}" 0
  run archive-env e559
  assert_status "${status}" 0
  assert_contains "${output}" "already archived"
}

test_arce_default_env_warns() {
  make_env e559 foo
  set_default_env e559
  run archive-env e559
  assert_status "${status}" 0
  assert_contains "${output}" "default environment"
  assert_contains "${output}" "e559 was archived"
  local body; body="$(cat "${ARTENV_ROOT}/envs/e559.toml")"
  assert_contains "${body}" "archived = true"
}

test_arce_notfound() {
  run archive-env nope
  assert_status "${status}" 1
  assert_contains "${output}" "environment not found"
}

test_arce_unknown_option() {
  run unarchive-env --bogus
  assert_status "${status}" 1
  assert_contains "${output}" "unknown option"
}

# --- ls / versions filtering ------------------------------------------------

test_ls_hides_archived_by_default() {
  make_env visible foo
  make_env retired foo
  run archive-env retired
  assert_status "${status}" 0
  run ls
  assert_status "${status}" 0
  assert_contains "${output}" "visible"
  assert_not_contains "${output}" "retired"
}

test_ls_all_shows_archived_with_suffix() {
  make_env visible foo
  make_env retired foo
  run archive-env retired
  assert_status "${status}" 0
  run ls --all
  assert_status "${status}" 0
  assert_contains "${output}" "visible"
  assert_contains "${output}" "retired (archived)"
}

test_ls_all_current_marker_with_archived() {
  make_env retired foo
  run archive-env retired
  assert_status "${status}" 0
  export ART_PROJECT=retired
  run ls -a
  unset ART_PROJECT
  assert_status "${status}" 0
  assert_contains "${output}" "* retired (archived)"
}

test_versions_hides_archived_by_default() {
  fake_native_version shown
  fake_native_version tucked
  run archive-version tucked
  assert_status "${status}" 0
  run versions
  assert_status "${status}" 0
  assert_contains "${output}" "shown"
  assert_not_contains "${output}" "tucked"
}

test_versions_all_shows_archived_with_suffix() {
  fake_native_version shown
  fake_native_version tucked
  run archive-version tucked
  assert_status "${status}" 0
  run versions --all
  assert_status "${status}" 0
  assert_contains "${output}" "shown"
  assert_contains "${output}" "tucked (archived)"
}

# --- register-env excludes archived versions from selection -----------------

test_register_env_all_archived_dies() {
  fake_native_version only
  run archive-version only
  assert_status "${status}" 0
  run_in "" register-env newenv
  assert_status "${status}" 1
  assert_contains "${output}" "all versions are archived"
}

test_register_env_select_excludes_archived() {
  fake_native_version keepver
  fake_native_version hidever
  run archive-version hidever
  assert_status "${status}" 0
  # feed EOF: register-env shows the version menu then fails on empty work dir.
  run_in "" register-env newenv
  assert_contains "${output}" "keepver"
  assert_not_contains "${output}" "hidever"
}

# --- dispatcher exposes the new subcommands ---------------------------------

test_commands_lists_archive() {
  run commands
  assert_status "${status}" 0
  assert_contains "${output}" "archive-version"
  assert_contains "${output}" "archive-env"
  assert_contains "${output}" "unarchive-version"
  assert_contains "${output}" "unarchive-env"
}
