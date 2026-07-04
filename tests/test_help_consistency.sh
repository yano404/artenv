#!/usr/bin/env bash
# shellcheck disable=SC2154  # status/output are set by run() in lib.sh
# shellcheck disable=SC2016  # single-quoted literals below are intentional
# Help consistency: every user-facing subcommand must handle -h/--help by
# printing its usage to stdout and exiting 0 -- never crash, never treat the
# flag as a positional argument.

# Living enumeration of every user-facing command invocation. Sub-actions are
# spelled out as space-separated invocations. Excluded on purpose: shell /
# sh-shell, --version, and the deprecated register-* shims (covered by their
# own inheritance checks below).
_HELP_COMMANDS=(
  "ls"
  "remove"
  "archive"
  "unarchive"
  "new"
  "doctor"
  "info"
  "default"
  "migrate"
  "commands"
  "register"
  "version"
  "version current"
  "version ls"
  "version register"
  "version remove"
  "version archive"
  "version unarchive"
  "version info"
  "version install"
  "templates"
  "templates ls"
  "templates repos"
  "templates update"
  "init"
)

# Data-driven: for every command, both -h and --help must exit 0 and render
# usage. The "--help" substring appears in every Options block, so it proves
# the usage text rendered. `init` is the one exception -- its help is the
# pyenv-style setup guide with no Options block -- so it is content-checked
# separately (see test_help_init_setup_guide); here it only asserts exit 0.
test_help_all_commands() {
  local cmd flag
  for cmd in "${_HELP_COMMANDS[@]}"; do
    for flag in -h --help; do
      # shellcheck disable=SC2086  # intentional word splitting of the invocation
      run ${cmd} ${flag}
      assert_status "${status}" 0 "(${cmd} ${flag})"
      if [[ "${cmd}" != "init" ]]; then
        assert_contains "${output}" "--help"
      fi
    done
  done
}

# Anti-regression: `-h` must be parsed before the interactive `select`, so it
# never falls through into the version/env registration prompts and never hits
# the `tmp_conf: unbound variable` crash.
test_help_version_register_no_interactive() {
  local flag
  for flag in -h --help; do
    # shellcheck disable=SC2086
    run version register ${flag}
    assert_status "${status}" 0 "(version register ${flag})"
    assert_contains "${output}" "--help"
    assert_not_contains "${output}" "Select version type"
    assert_not_contains "${output}" "unbound variable"
  done
}

test_help_register_no_interactive() {
  local flag
  for flag in -h --help; do
    # shellcheck disable=SC2086
    run register ${flag}
    assert_status "${status}" 0 "(register ${flag})"
    assert_contains "${output}" "--help"
    assert_not_contains "${output}" "Select the artemis version"
    assert_not_contains "${output}" "unbound variable"
  done
}

# Deprecated shims inherit help from the canonical command they exec into.
# ARTENV_NO_DEPRECATION=1 (set by setup_sandbox) keeps stdout clean.
test_help_shim_inheritance() {
  run register-env -h
  assert_status "${status}" 0
  assert_contains "${output}" "--help"

  run register-version -h
  assert_status "${status}" 0
  assert_contains "${output}" "--help"
}

# init is special: `-h/--help` prints the setup guide (no side effects), while
# the canonical `init -` must still emit the shell function -- proving `-` was
# not mistaken for an unknown option.
test_help_init_setup_guide() {
  run init -h
  assert_status "${status}" 0
  assert_contains "${output}" 'eval "$(artenv init -)"'

  run init --help
  assert_status "${status}" 0
  assert_contains "${output}" 'eval "$(artenv init -)"'

  run init -
  assert_status "${status}" 0
  assert_contains "${output}" "artenv()"
}
