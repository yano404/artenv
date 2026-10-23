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

_repo_cmds_setup_myrepo() {
  local repo; repo="$(make_template_repo alpha)"
  write_repo_conf myrepo "${repo}"
  run templates update
  assert_status "${status}" 0
}

test_disable_repo_hides_and_keeps_cache() {
  _repo_cmds_setup_myrepo
  run templates disable-repo myrepo
  assert_status "${status}" 0
  assert_contains "${output}" "myrepo was disabled"
  [[ "$(toml_field "${ARTENV_ROOT}/template-repos/myrepo.toml" repo enabled)" == "false" ]] || fail "enabled should be false"
  run templates ls
  assert_not_contains "${output}" "myrepo/alpha"
  assert_file "${ARTENV_ROOT}/templates/myrepo/alpha/file.txt"
}

test_enable_repo_restores() {
  _repo_cmds_setup_myrepo
  run templates disable-repo myrepo
  assert_status "${status}" 0
  run templates enable-repo myrepo
  assert_status "${status}" 0
  assert_contains "${output}" "myrepo was enabled"
  run templates ls
  assert_contains "${output}" "myrepo/alpha"
}

test_disable_repo_idempotent() {
  _repo_cmds_setup_myrepo
  run templates enable-repo myrepo
  assert_status "${status}" 0
  assert_contains "${output}" "myrepo is already enabled"
  run templates disable-repo myrepo
  assert_status "${status}" 0
  run templates disable-repo myrepo
  assert_status "${status}" 0
  assert_contains "${output}" "myrepo is already disabled"
}

test_disable_repo_preserves_other_lines() {
  local conf="${ARTENV_ROOT}/template-repos/myrepo.toml"
  mkdir -p "${ARTENV_ROOT}/template-repos"
  {
    printf '# group: ribf\n'
    printf '[repo]\n'
    printf 'url = "file:///nonexistent"\n'
    printf 'enabled = true\n'
    printf 'ref = "main"\n'
    printf 'custom = "x"\n'
  } > "${conf}"
  cp "${conf}" "${ARTENV_ROOT}/.orig.toml"

  run templates disable-repo myrepo
  assert_status "${status}" 0
  local diffout
  diffout="$(diff "${ARTENV_ROOT}/.orig.toml" "${conf}" || true)"
  assert_contains "${diffout}" "enabled = true"
  assert_not_contains "${diffout}" "ref ="
  assert_not_contains "${diffout}" "custom"
  assert_not_contains "${diffout}" "group"

  run templates enable-repo myrepo
  assert_status "${status}" 0
  assert_contains "$(grep -n '' "${conf}")" "1:# group: ribf"
  assert_contains "$(grep -n '' "${conf}")" "3:url = \"file:///nonexistent\""
  assert_contains "$(grep -n '' "${conf}")" "5:ref = \"main\""
  assert_contains "$(grep -n '' "${conf}")" "6:custom = \"x\""
  [[ "$(toml_field "${conf}" repo enabled)" == "true" ]] || fail "enabled should be true"
}

test_disable_repo_missing_enabled_line() {
  local conf="${ARTENV_ROOT}/template-repos/myrepo.toml"
  mkdir -p "${ARTENV_ROOT}/template-repos"
  printf '[repo]\nurl = "file:///nonexistent"\n' > "${conf}"
  run templates disable-repo myrepo
  assert_status "${status}" 0
  assert_contains "${output}" "myrepo was disabled"
  [[ "$(toml_field "${conf}" repo enabled)" == "false" ]] || fail "enabled should be false"
}

test_enable_disable_repo_errors() {
  local sub
  for sub in enable-repo disable-repo; do
    run templates "${sub}" nosuch
    assert_status "${status}" 1
    assert_contains "${output}" "no such template repository"
    run templates "${sub}" local
    assert_status "${status}" 1
    assert_contains "${output}" "reserved"
    run templates "${sub}"
    assert_status "${status}" 1
    assert_contains "${output}" "usage"
    run templates "${sub}" -x
    assert_status "${status}" 1
    assert_contains "${output}" "unknown option: -x"
  done
}

test_remove_repo_deletes_conf_and_cache() {
  _repo_cmds_setup_myrepo
  run templates remove-repo myrepo
  assert_status "${status}" 0
  assert_contains "${output}" "removed config: template-repos/myrepo.toml"
  assert_contains "${output}" "removed cache: templates/myrepo/"
  assert_no_file "${ARTENV_ROOT}/template-repos/myrepo.toml"
  assert_no_file "${ARTENV_ROOT}/templates/myrepo"
  run templates repos
  assert_not_contains "${output}" "myrepo"
}

test_remove_repo_without_cache() {
  local repo; repo="$(make_template_repo alpha)"
  write_repo_conf myrepo "${repo}"
  run templates remove-repo myrepo
  assert_status "${status}" 0
  assert_contains "${output}" "removed config"
  assert_not_contains "${output}" "removed cache"
  assert_no_file "${ARTENV_ROOT}/template-repos/myrepo.toml"
}

test_remove_repo_default_not_reseeded() {
  seed_share_default
  run templates repos
  assert_status "${status}" 0
  assert_contains "${output}" "default"
  run templates remove-repo default
  assert_status "${status}" 0
  run templates repos
  assert_not_contains "${output}" "default"
}

test_remove_repo_keeps_created_project() {
  _repo_cmds_setup_myrepo
  mkdir -p "${ARTENV_ROOT}/.fixtures"
  run new "${ARTENV_ROOT}/.fixtures/proj" -t myrepo/alpha
  assert_status "${status}" 0
  run templates remove-repo myrepo
  assert_status "${status}" 0
  assert_file "${ARTENV_ROOT}/.fixtures/proj/file.txt"
}

test_remove_repo_errors() {
  mkdir -p "${ARTENV_ROOT}/templates/local/keep"
  run templates remove-repo nosuch
  assert_status "${status}" 1
  assert_contains "${output}" "no such template repository"
  run templates remove-repo local
  assert_status "${status}" 1
  assert_contains "${output}" "reserved"
  [[ -d "${ARTENV_ROOT}/templates/local/keep" ]] || fail "templates/local touched"
  run templates remove-repo
  assert_status "${status}" 1
  assert_contains "${output}" "usage"
  run templates remove-repo -x
  assert_status "${status}" 1
  assert_contains "${output}" "unknown option: -x"
}
