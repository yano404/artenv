#!/usr/bin/env bash
# shellcheck disable=SC2154  # status/output are set by run()/run_in() in lib.sh
# shellcheck disable=SC2016  # single quotes are intentional: $1 expands inside
#                            # the generated fake-editor script, not here
# Tests for `artenv edit [env]` and `artenv version edit [version]`.

# Write an executable fake-editor script into the sandbox so it is cleaned up
# with ARTENV_ROOT. The script receives the config path as $1.
#   write_fake_editor <script_name> <body...>
write_fake_editor() {
  local name="$1"; shift
  local path="${ARTENV_ROOT}/${name}"
  {
    printf '#!/usr/bin/env bash\n'
    printf '%s\n' "$@"
  } > "${path}"
  chmod +x "${path}"
  printf '%s' "${path}"
}

# =============================================================================
# artenv edit
# =============================================================================

test_edit_happy_env_arg() {
  make_env e1 v1
  export EDITOR=true
  run edit e1
  assert_status "${status}" 0
}

test_edit_noarg_uses_art_project() {
  make_env e1 v1
  export ART_PROJECT=e1
  export EDITOR=true
  run edit
  assert_status "${status}" 0
}

test_edit_noarg_uses_art_project_edits_right_file() {
  make_env e1 v1
  make_env e2 v1
  export ART_PROJECT=e1
  local marker; marker="$(write_fake_editor fakeed.sh 'printf "# marker-e1\n" >> "$1"')"
  export EDITOR="${marker}"
  run edit
  assert_status "${status}" 0
  grep -q "marker-e1" "${ARTENV_ROOT}/envs/e1.toml" || fail "expected marker in e1.toml"
  grep -q "marker-e1" "${ARTENV_ROOT}/envs/e2.toml" && fail "marker leaked into e2.toml"
  return 0
}

test_edit_noarg_no_env_set() {
  export EDITOR=true
  run edit
  assert_status "${status}" 1
  assert_contains "${output}" "is not set"
}

test_edit_missing_target() {
  export EDITOR=true
  run edit ghost
  assert_status "${status}" 1
  assert_contains "${output}" "not found"
}

test_edit_help_short() {
  run edit -h
  assert_status "${status}" 0
  assert_contains "${output}" "--help"
}

test_edit_help_long() {
  run edit --help
  assert_status "${status}" 0
  assert_contains "${output}" "--help"
}

test_edit_editor_actually_receives_file() {
  make_env e1 v1
  local marker; marker="$(write_fake_editor fakeed.sh 'printf "# edited-marker\n" >> "$1"')"
  export EDITOR="${marker}"
  run edit e1
  assert_status "${status}" 0
  grep -q "edited-marker" "${ARTENV_ROOT}/envs/e1.toml" || fail "editor did not touch the config file"
}

test_edit_postedit_invalid_toml() {
  make_env e1 v1
  local badeditor; badeditor="$(write_fake_editor fakeed.sh 'printf "x = = =\n" > "$1"')"
  export EDITOR="${badeditor}"
  run edit e1
  assert_status "${status}" 1
  assert_contains "${output}" "not valid TOML"
}

test_edit_postedit_valid_toml() {
  make_env e1 v1
  local goodeditor; goodeditor="$(write_fake_editor fakeed.sh 'printf "# still-valid\n" >> "$1"')"
  export EDITOR="${goodeditor}"
  run edit e1
  assert_status "${status}" 0
  assert_not_contains "${output}" "not valid TOML"
}

test_edit_visual_takes_precedence_over_editor() {
  make_env e1 v1
  local visual editor
  visual="$(write_fake_editor fakvis.sh 'printf "# VISUAL_RAN\n" >> "$1"')"
  editor="$(write_fake_editor fakedt.sh 'printf "# EDITOR_RAN\n" >> "$1"')"
  export VISUAL="${visual}"
  export EDITOR="${editor}"
  run edit e1
  assert_status "${status}" 0
  grep -q "VISUAL_RAN" "${ARTENV_ROOT}/envs/e1.toml" || fail "expected VISUAL editor to run"
  grep -q "EDITOR_RAN" "${ARTENV_ROOT}/envs/e1.toml" && fail "EDITOR should not have run when VISUAL is set"
  return 0
}

test_edit_in_commands() {
  run commands
  assert_contains "${output}" "edit"
}

# =============================================================================
# artenv version edit
# =============================================================================

test_vedit_happy_version_arg() {
  fake_native_version v1
  export EDITOR=true
  run version edit v1
  assert_status "${status}" 0
}

test_vedit_noarg_uses_art_version() {
  fake_native_version v1
  export ART_VERSION=v1
  export EDITOR=true
  run version edit
  assert_status "${status}" 0
}

test_vedit_noarg_uses_art_version_edits_right_file() {
  fake_native_version v1
  fake_native_version v2
  export ART_VERSION=v1
  local marker; marker="$(write_fake_editor fakeed.sh 'printf "# marker-v1\n" >> "$1"')"
  export EDITOR="${marker}"
  run version edit
  assert_status "${status}" 0
  grep -q "marker-v1" "${ARTENV_ROOT}/versions/v1.toml" || fail "expected marker in v1.toml"
  grep -q "marker-v1" "${ARTENV_ROOT}/versions/v2.toml" && fail "marker leaked into v2.toml"
  return 0
}

test_vedit_noarg_no_version_set() {
  export EDITOR=true
  run version edit
  assert_status "${status}" 1
  assert_contains "${output}" "is not set"
}

test_vedit_missing_target() {
  export EDITOR=true
  run version edit ghost
  assert_status "${status}" 1
  assert_contains "${output}" "not found"
}

test_vedit_help_short() {
  run version edit -h
  assert_status "${status}" 0
  assert_contains "${output}" "--help"
}

test_vedit_help_long() {
  run version edit --help
  assert_status "${status}" 0
  assert_contains "${output}" "--help"
}

test_vedit_editor_actually_receives_file() {
  fake_native_version v1
  local marker; marker="$(write_fake_editor fakeed.sh 'printf "# edited-marker\n" >> "$1"')"
  export EDITOR="${marker}"
  run version edit v1
  assert_status "${status}" 0
  grep -q "edited-marker" "${ARTENV_ROOT}/versions/v1.toml" || fail "editor did not touch the config file"
}

test_vedit_postedit_invalid_toml() {
  fake_native_version v1
  local badeditor; badeditor="$(write_fake_editor fakeed.sh 'printf "x = = =\n" > "$1"')"
  export EDITOR="${badeditor}"
  run version edit v1
  assert_status "${status}" 1
  assert_contains "${output}" "not valid TOML"
}

test_vedit_postedit_valid_toml() {
  fake_native_version v1
  local goodeditor; goodeditor="$(write_fake_editor fakeed.sh 'printf "# still-valid\n" >> "$1"')"
  export EDITOR="${goodeditor}"
  run version edit v1
  assert_status "${status}" 0
  assert_not_contains "${output}" "not valid TOML"
}

test_vedit_visual_takes_precedence_over_editor() {
  fake_native_version v1
  local visual editor
  visual="$(write_fake_editor fakvis.sh 'printf "# VISUAL_RAN\n" >> "$1"')"
  editor="$(write_fake_editor fakedt.sh 'printf "# EDITOR_RAN\n" >> "$1"')"
  export VISUAL="${visual}"
  export EDITOR="${editor}"
  run version edit v1
  assert_status "${status}" 0
  grep -q "VISUAL_RAN" "${ARTENV_ROOT}/versions/v1.toml" || fail "expected VISUAL editor to run"
  grep -q "EDITOR_RAN" "${ARTENV_ROOT}/versions/v1.toml" && fail "EDITOR should not have run when VISUAL is set"
  return 0
}

test_vedit_not_in_commands() {
  run commands
  assert_not_contains "${output}" "version-edit"
}

test_vedit_listed_in_version_help() {
  run version --help
  assert_status "${status}" 0
  assert_contains "${output}" "edit"
}
