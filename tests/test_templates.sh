#!/usr/bin/env bash
# shellcheck disable=SC2154  # status/output are set by run()/run_in() in lib.sh
# Tests for: artenv templates group + `new' template resolution (v2.1 phase 2)
#
# Every test runs against the isolated ARTENV_ROOT sandbox. Template repos are
# faked with a real local git repo created under a temp dir; the repo `url' is
# a plain filesystem path, so no network access is needed.

# --- template-specific fixtures --------------------------------------------
#
# Fixture git repos live under ${ARTENV_ROOT}/.fixtures/ so the sandbox teardown
# in tests/lib.sh removes them automatically. That dir is outside templates/ and
# template-repos/, so artenv never scans it.

_TEMPLATE_REPO_N=0

# Create a local git repo with the given template dirs and print its path.
# Usage: make_template_repo <tmpl> [<tmpl>...]
make_template_repo() {
  _TEMPLATE_REPO_N=$((_TEMPLATE_REPO_N + 1))
  local repo="${ARTENV_ROOT}/.fixtures/repo${_TEMPLATE_REPO_N}"
  mkdir -p "${repo}"
  git -C "${repo}" init -q -b main
  git -C "${repo}" config user.email test@example.com
  git -C "${repo}" config user.name test
  local t
  for t in "$@"; do
    mkdir -p "${repo}/${t}"
    printf 'content of %s\n' "${t}" > "${repo}/${t}/file.txt"
  done
  git -C "${repo}" add -A
  git -C "${repo}" commit -q -m init
  printf '%s\n' "${repo}"
}

# Write template-repos/<name>.toml. Usage: write_repo_conf <name> <url> [enabled] [ref] [desc]
write_repo_conf() {
  local name="$1" url="$2" enabled="${3:-true}" ref="${4:-main}" desc="${5:-}"
  mkdir -p "${ARTENV_ROOT}/template-repos"
  {
    printf '[repo]\n'
    printf 'url = "file://%s"\n' "${url}"
    printf 'enabled = %s\n' "${enabled}"
    printf 'ref = "%s"\n' "${ref}"
    [[ -n "${desc}" ]] && printf 'description = "%s"\n' "${desc}"
  } > "${ARTENV_ROOT}/template-repos/${name}.toml"
}

# Seed a local/ template so migration behaviour can be exercised.
seed_local_standard() {
  mkdir -p "${ARTENV_ROOT}/templates/local/standard"
  printf 'local standard\n' > "${ARTENV_ROOT}/templates/local/standard/file.txt"
}

# TEMPLATE_REPOS holds fixture repo dirs to clean up after each test.
_templates_cleanup() {
  local d
  for d in "${TEMPLATE_REPOS[@]:-}"; do
    [[ -n "${d}" && -d "${d}" ]] && rm -rf "${d}"
  done
  TEMPLATE_REPOS=()
}

# --- templates update -------------------------------------------------------

test_templates_update_clones_cache() {
  TEMPLATE_REPOS=()
  local repo; repo="$(make_template_repo alpha beta)"
  write_repo_conf myrepo "${repo}"

  run templates update
  assert_status "${status}" 0
  assert_contains "${output}" "cloned"
  assert_contains "${output}" "myrepo"
  assert_file "${ARTENV_ROOT}/templates/myrepo/alpha/file.txt"
  assert_file "${ARTENV_ROOT}/templates/myrepo/beta/file.txt"
  # cache is a plain tree, no working git metadata
  assert_no_file "${ARTENV_ROOT}/templates/myrepo/.git"
  _templates_cleanup
}

test_templates_update_idempotent() {
  TEMPLATE_REPOS=()
  local repo; repo="$(make_template_repo alpha)"
  write_repo_conf myrepo "${repo}"

  run templates update
  assert_status "${status}" 0
  assert_contains "${output}" "cloned"

  run templates update
  assert_status "${status}" 0
  assert_contains "${output}" "updated"
  assert_file "${ARTENV_ROOT}/templates/myrepo/alpha/file.txt"
  _templates_cleanup
}

test_templates_update_skips_local() {
  TEMPLATE_REPOS=()
  seed_local_standard
  run templates update local
  assert_status "${status}" 0
  assert_contains "${output}" "skipped"
  assert_contains "${output}" "reserved"
  _templates_cleanup
}

test_templates_update_skips_disabled() {
  TEMPLATE_REPOS=()
  local repo; repo="$(make_template_repo alpha)"
  write_repo_conf off "${repo}" false

  run templates update
  assert_status "${status}" 0
  assert_contains "${output}" "skipped"
  assert_contains "${output}" "disabled"
  assert_no_file "${ARTENV_ROOT}/templates/off/alpha/file.txt"
  _templates_cleanup
}

test_templates_update_partial_failure_exits_1() {
  TEMPLATE_REPOS=()
  local repo; repo="$(make_template_repo alpha)"
  write_repo_conf good "${repo}"
  # broken repo: url points nowhere
  mkdir -p "${ARTENV_ROOT}/template-repos"
  printf '[repo]\nurl = "file:///nonexistent/nope.git"\nref = "main"\n' \
    > "${ARTENV_ROOT}/template-repos/broken.toml"

  run templates update
  assert_status "${status}" 1
  assert_contains "${output}" "failed"
  assert_contains "${output}" "broken"
  # the good repo is still cloned despite the sibling failure
  assert_file "${ARTENV_ROOT}/templates/good/alpha/file.txt"
  _templates_cleanup
}

test_templates_update_unknown_repo_fails() {
  TEMPLATE_REPOS=()
  run templates update ghost
  assert_status "${status}" 1
  assert_contains "${output}" "no such repo"
  _templates_cleanup
}

# --- templates repos --------------------------------------------------------

test_templates_repos_lists() {
  TEMPLATE_REPOS=()
  local repo; repo="$(make_template_repo alpha)"
  write_repo_conf myrepo "${repo}" true main "my templates"

  run templates repos
  assert_status "${status}" 0
  assert_contains "${output}" "myrepo"
  assert_contains "${output}" "my templates"
  assert_contains "${output}" "true"
  # not yet cached
  assert_contains "${output}" "no"

  run templates update
  run templates repos
  assert_contains "${output}" "yes"
  _templates_cleanup
}

test_templates_repos_shows_local() {
  TEMPLATE_REPOS=()
  seed_local_standard
  run templates repos
  assert_status "${status}" 0
  assert_contains "${output}" "local"
  _templates_cleanup
}

test_templates_repos_disabled_flag() {
  TEMPLATE_REPOS=()
  local repo; repo="$(make_template_repo alpha)"
  write_repo_conf off "${repo}" false
  run templates repos
  assert_status "${status}" 0
  assert_contains "${output}" "off"
  assert_contains "${output}" "false"
  _templates_cleanup
}

# --- templates ls -----------------------------------------------------------

test_templates_ls_shows_repo_and_local() {
  TEMPLATE_REPOS=()
  seed_local_standard
  local repo; repo="$(make_template_repo alpha beta)"
  write_repo_conf myrepo "${repo}"
  run templates update

  run templates ls
  assert_status "${status}" 0
  assert_contains "${output}" "local/standard"
  assert_contains "${output}" "myrepo/alpha"
  assert_contains "${output}" "myrepo/beta"
  _templates_cleanup
}

test_templates_ls_hides_disabled() {
  TEMPLATE_REPOS=()
  local repo; repo="$(make_template_repo alpha)"
  write_repo_conf myrepo "${repo}"
  run templates update
  # now disable it; the cache still exists but must be hidden
  write_repo_conf myrepo "${repo}" false

  run templates ls
  assert_status "${status}" 0
  assert_not_contains "${output}" "myrepo/alpha"
  _templates_cleanup
}

# --- templates group dispatcher --------------------------------------------

test_templates_group_help() {
  run templates -h
  assert_status "${status}" 0
  assert_contains "${output}" "usage: artenv templates"
}

test_templates_group_bare_help() {
  run templates
  assert_status "${status}" 0
  assert_contains "${output}" "usage: artenv templates"
}

test_templates_group_unknown_action() {
  run templates bogus
  assert_status "${status}" 1
  assert_contains "${output}" "no such templates subcommand"
}

test_templates_group_unknown_option() {
  run templates --bogus
  assert_status "${status}" 1
  assert_contains "${output}" "unknown option"
}

# --- new: template resolution ----------------------------------------------

test_new_qualified_template() {
  TEMPLATE_REPOS=()
  local repo; repo="$(make_template_repo alpha)"
  write_repo_conf myrepo "${repo}"
  run templates update

  run new "${ARTENV_ROOT}/work" -t myrepo/alpha
  assert_status "${status}" 0
  assert_file "${ARTENV_ROOT}/work/file.txt"
  _templates_cleanup
}

test_new_unqualified_unique() {
  TEMPLATE_REPOS=()
  local repo; repo="$(make_template_repo alpha)"
  write_repo_conf myrepo "${repo}"
  run templates update

  run new "${ARTENV_ROOT}/work" -t alpha
  assert_status "${status}" 0
  assert_file "${ARTENV_ROOT}/work/file.txt"
  _templates_cleanup
}

test_new_unqualified_ambiguous_dies() {
  TEMPLATE_REPOS=()
  seed_local_standard
  local repo; repo="$(make_template_repo standard)"
  write_repo_conf myrepo "${repo}"
  run templates update

  run new "${ARTENV_ROOT}/work" -t standard
  assert_status "${status}" 1
  assert_contains "${output}" "ambiguous"
  assert_no_file "${ARTENV_ROOT}/work/file.txt"
  _templates_cleanup
}

test_new_template_not_found_dies() {
  TEMPLATE_REPOS=()
  run new "${ARTENV_ROOT}/work" -t nope
  assert_status "${status}" 1
  assert_contains "${output}" "template not found"
  _templates_cleanup
}

test_new_local_standard() {
  TEMPLATE_REPOS=()
  seed_local_standard
  run new "${ARTENV_ROOT}/work" -t local/standard
  assert_status "${status}" 0
  assert_file "${ARTENV_ROOT}/work/file.txt"
  _templates_cleanup
}

test_new_rejects_path_escape() {
  TEMPLATE_REPOS=()
  run new "${ARTENV_ROOT}/work" -t ../etc
  assert_status "${status}" 1
  assert_contains "${output}" "invalid template name"
  _templates_cleanup
}

test_new_unknown_option_dies() {
  TEMPLATE_REPOS=()
  run new "${ARTENV_ROOT}/work" --bogus
  assert_status "${status}" 1
  assert_contains "${output}" "unknown option"
  _templates_cleanup
}

test_new_non_empty_dir_dies() {
  TEMPLATE_REPOS=()
  seed_local_standard
  mkdir -p "${ARTENV_ROOT}/work"
  touch "${ARTENV_ROOT}/work/keep"
  run new "${ARTENV_ROOT}/work" -t local/standard
  assert_status "${status}" 1
  assert_contains "${output}" "not empty"
  _templates_cleanup
}

test_new_no_template_non_tty_dies() {
  TEMPLATE_REPOS=()
  seed_local_standard
  run_in "" new "${ARTENV_ROOT}/work"
  assert_status "${status}" 1
  assert_contains "${output}" "not a tty"
  _templates_cleanup
}
