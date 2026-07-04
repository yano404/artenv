#!/usr/bin/env bash
# shellcheck disable=SC2154  # status/output are set by run()/run_in() in lib.sh
# Tests for: `artenv commands` reflects the v2.1 grouping.
# The `version` group is a top-level command; its sub-actions (artenv-version-*)
# are NOT top-level commands. Old names remain (as shims) for compatibility.

test_cmds_includes_version_group() {
  run commands
  assert_status "${status}" 0
  # `version` must appear as its own line (word-boundary check)
  [[ $'\n'"${output}"$'\n' == *$'\nversion\n'* ]] || \
    fail "expected 'version' as a top-level command; got: ${output}"
}

test_cmds_excludes_version_subactions() {
  run commands
  assert_status "${status}" 0
  assert_not_contains "${output}" "version-ls"
  assert_not_contains "${output}" "version-register"
  assert_not_contains "${output}" "version-remove"
  assert_not_contains "${output}" "version-archive"
  assert_not_contains "${output}" "version-unarchive"
  assert_not_contains "${output}" "version-install"
  assert_not_contains "${output}" "version-current"
}

test_cmds_includes_bare_env_verbs() {
  run commands
  assert_status "${status}" 0
  local c
  for c in register remove archive unarchive; do
    [[ $'\n'"${output}"$'\n' == *$'\n'"${c}"$'\n'* ]] || \
      fail "expected '${c}' as a top-level command; got: ${output}"
  done
}

test_cmds_includes_deprecated_shims() {
  run commands
  assert_status "${status}" 0
  local c
  for c in versions register-version remove-version archive-version \
           unarchive-version install register-env remove-env \
           archive-env unarchive-env; do
    assert_contains "${output}" "${c}"
  done
}
