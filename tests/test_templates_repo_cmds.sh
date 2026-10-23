#!/usr/bin/env bash
# shellcheck disable=SC2154  # status/output are set by run()/run_in() in lib.sh
# Tests for: templates add-repo/remove-repo/enable-repo/disable-repo support
# (helpers in libexec/util.sh, orphan-cache hiding). Fixtures come from
# tests/test_templates.sh (make_template_repo / write_repo_conf).

test_templates_ls_hides_orphan_cache() {
  mkdir -p "${ARTENV_ROOT}/templates/ghost/alpha"
  run templates ls
  assert_status "${status}" 0
  assert_not_contains "${output}" "ghost/alpha"
}

test_new_qualified_orphan_cache_still_works() {
  mkdir -p "${ARTENV_ROOT}/templates/ghost/alpha"
  printf 'x\n' > "${ARTENV_ROOT}/templates/ghost/alpha/file.txt"
  mkdir -p "${ARTENV_ROOT}/.fixtures"
  run new "${ARTENV_ROOT}/.fixtures/proj" -t ghost/alpha
  assert_status "${status}" 0
  assert_file "${ARTENV_ROOT}/.fixtures/proj/file.txt"
}

test_new_qualified_disabled_repo_still_works() {
  local repo; repo="$(make_template_repo alpha)"
  write_repo_conf myrepo "${repo}"
  run templates update
  assert_status "${status}" 0
  write_repo_conf myrepo "${repo}" false
  mkdir -p "${ARTENV_ROOT}/.fixtures"
  run new "${ARTENV_ROOT}/.fixtures/proj" -t myrepo/alpha
  assert_status "${status}" 0
  assert_file "${ARTENV_ROOT}/.fixtures/proj/file.txt"
}
