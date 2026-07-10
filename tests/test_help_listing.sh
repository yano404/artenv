#!/usr/bin/env bash
# shellcheck disable=SC2154  # status/output are set by run() in lib.sh
# Regression tests for GitHub issue #53: `edit` was implemented and had its
# own -h/--help (covered by test_help_consistency.sh), but was missing from
# the `artenv -h` command listing in libexec/artenv-help. test_help_consistency.sh
# only checks that each command's OWN -h works; nothing asserted that every
# command in `artenv commands` is actually advertised in the top-level `-h`
# listing. That gap is what let `edit` go unlisted. This file closes it.

# Word-boundary substring check: true if `needle` appears in `haystack` as a
# standalone token, where letters/digits/underscore/hyphen count as "word"
# characters (so e.g. "version" does not spuriously match inside
# "register-version", and "ls" does not spuriously match inside "false").
# Plain substring assert_contains is NOT enough here -- see the false-positive
# example above.
_help_listing_word_present() { # <haystack> <needle>
  local haystack="$1" needle="$2"
  local re="(^|[^A-Za-z0-9_-])${needle}([^A-Za-z0-9_-]|\$)"
  [[ "${haystack}" =~ ${re} ]]
}

# Core coverage check: every top-level command that `artenv commands` lists
# must appear as a word somewhere in `artenv -h` (= `artenv help`) output.
# This is exactly the regression class for issue #53: `edit` was a real,
# working command (artenv-edit existed, had its own -h) yet absent from the
# -h listing entirely.
#
# Caveat (documented, not a bug in this test): this loop alone would NOT have
# caught the original #53 regression, because "edit" also occurs in the
# Version-commands summary line
# ("...archive/unarchive/edit/install/current..."), so the word is present in
# `-h` output even when the dedicated env `edit` listing line is deleted.
# That is exactly why test_help_listing_edit_env_line and
# test_help_listing_edit_version_summary below assert on the two occurrences
# individually -- confirmed experimentally: deleting just the env `edit` line
# from libexec/artenv-help left this coverage loop green.
test_help_listing_all_commands_advertised() {
  run commands
  assert_status "${status}" 0
  local cmds_output="${output}"

  run -h
  assert_status "${status}" 0
  local help_output="${output}"

  local cmd
  local -a missing=()
  while IFS= read -r cmd; do
    [[ -n "${cmd}" ]] || continue
    if ! _help_listing_word_present "${help_output}" "${cmd}"; then
      missing+=("${cmd}")
    fi
  done <<< "${cmds_output}"

  if [[ "${#missing[@]}" -gt 0 ]]; then
    fail "commands missing from 'artenv -h' listing: ${missing[*]}"
  fi
}

# Pinpoint regression #1: the env `edit` command must have its own dedicated
# line in the Environment commands block, not just an incidental mention
# elsewhere.
test_help_listing_edit_env_line() {
  run -h
  assert_status "${status}" 0
  assert_contains "${output}" "edit              Open an environment's config in"
}

# Pinpoint regression #2: the Version-commands summary line must still list
# `edit` among the version sub-actions (ls/register/remove/archive/
# unarchive/edit/install/current).
test_help_listing_edit_version_summary() {
  run -h
  assert_status "${status}" 0
  assert_contains "${output}" "unarchive/edit/install"
}

# Sanity: the grouped commands (version/templates) are advertised as
# "<name> <cmd>" rather than as their own itemized entries, and the
# deprecated-aliases section is still present. These are not issue #53
# regressions by themselves, but they document why `version` and `templates`
# legitimately pass the coverage loop above (real word-boundary matches, not
# a fluke of the parenthetical summaries).
test_help_listing_group_commands_present() {
  run -h
  assert_status "${status}" 0
  assert_contains "${output}" "version <cmd>"
  assert_contains "${output}" "templates <cmd>"
  assert_contains "${output}" "Deprecated aliases (kept for compatibility):"
}
