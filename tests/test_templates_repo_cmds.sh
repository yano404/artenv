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

# --- templates add-repo ---------------------------------------------------

test_add_repo_registers_and_fetches() {
  local repo; repo="$(make_template_repo alpha)"
  local conf="${ARTENV_ROOT}/template-repos/ribf.toml"
  run templates add-repo ribf "file://${repo}"
  assert_status "${status}" 0
  assert_contains "${output}" "added"
  assert_contains "${output}" "cloned"
  [[ "$(toml_field "${conf}" repo url)" == "file://${repo}" ]] || fail "url mismatch"
  [[ "$(toml_field "${conf}" repo enabled)" == "true" ]] || fail "enabled should be true"
  run templates ls
  assert_contains "${output}" "ribf/alpha"
}

test_add_repo_ref_and_description() {
  local repo; repo="$(make_template_repo alpha)"
  local conf="${ARTENV_ROOT}/template-repos/ribf.toml"
  run templates add-repo ribf "file://${repo}" --ref main --description "RIBF group"
  assert_status "${status}" 0
  [[ "$(toml_field "${conf}" repo ref)" == "main" ]] || fail "ref mismatch"
  [[ "$(toml_field "${conf}" repo description)" == "RIBF group" ]] || fail "description mismatch"
}

test_add_repo_options_before_positionals() {
  run templates add-repo --no-fetch --description "d" ribf "file:///x"
  assert_status "${status}" 0
  assert_file "${ARTENV_ROOT}/template-repos/ribf.toml"
}

test_add_repo_fetch_failure_rolls_back() {
  run templates add-repo ribf "file://${ARTENV_ROOT}/.fixtures/nope"
  assert_status "${status}" 1
  assert_contains "${output}" "rolled back"
  assert_no_file "${ARTENV_ROOT}/template-repos/ribf.toml"
  assert_no_file "${ARTENV_ROOT}/templates/ribf"
}

test_add_repo_no_fetch_keeps_registration() {
  run templates add-repo ribf "file://${ARTENV_ROOT}/.fixtures/nope" --no-fetch
  assert_status "${status}" 0
  assert_file "${ARTENV_ROOT}/template-repos/ribf.toml"
  assert_no_file "${ARTENV_ROOT}/templates/ribf"
  assert_contains "${output}" "artenv templates update ribf"
}

test_add_repo_duplicate_dies() {
  local conf="${ARTENV_ROOT}/template-repos/ribf.toml"
  run templates add-repo ribf "file:///one" --no-fetch
  assert_status "${status}" 0
  local before; before="$(cat "${conf}")"
  run templates add-repo ribf "file:///two" --no-fetch
  assert_status "${status}" 1
  assert_contains "${output}" "already exists"
  [[ "$(cat "${conf}")" == "${before}" ]] || fail "config changed by duplicate add"
}

test_add_repo_escapes_quotes() {
  local desc='say "hi" \ back'
  run templates add-repo ribf "file:///x" --description "${desc}" --no-fetch
  assert_status "${status}" 0
  [[ "$(toml_field "${ARTENV_ROOT}/template-repos/ribf.toml" repo description)" == "${desc}" ]] \
    || fail "description not round-tripped"
  run templates repos
  assert_contains "${output}" "${desc}"
}

test_add_repo_newline_rejected() {
  run templates add-repo ribf "file:///x" --description $'a\nb' --no-fetch
  assert_status "${status}" 1
  assert_contains "${output}" "newline"
  assert_no_file "${ARTENV_ROOT}/template-repos/ribf.toml"
}

test_add_repo_orphan_cache_replaced() {
  mkdir -p "${ARTENV_ROOT}/templates/ribf/stale"
  run templates add-repo ribf "file:///x" --no-fetch
  assert_status "${status}" 0
  assert_contains "${output}" "removed stale cache"
  assert_no_file "${ARTENV_ROOT}/templates/ribf"
  run templates ls
  assert_not_contains "${output}" "ribf/stale"
}

test_add_repo_invalid_value_leaves_orphan_cache() {
  mkdir -p "${ARTENV_ROOT}/templates/ribf/stale"
  run templates add-repo ribf "file:///x" --description $'a\nb' --no-fetch
  assert_status "${status}" 1
  [[ -d "${ARTENV_ROOT}/templates/ribf/stale" ]] || fail "cache removed before validation"
}

test_add_repo_fresh_install_seeds_default() {
  seed_share_default
  rm -rf "${ARTENV_ROOT}/template-repos"
  run templates add-repo ribf "file:///x" --no-fetch
  assert_status "${status}" 0
  run templates repos
  assert_contains "${output}" "default"
  assert_contains "${output}" "ribf"
}

test_add_repo_bad_names() {
  local n
  for n in local -x .x a/b ..; do
    run templates add-repo "${n}" "file:///x" --no-fetch
    assert_status "${status}" 1 "(name ${n})"
    assert_no_file "${ARTENV_ROOT}/template-repos/${n}.toml"
  done
  run templates add-repo
  assert_status "${status}" 1
  assert_contains "${output}" "usage: artenv templates add-repo"
  run templates add-repo ribf
  assert_status "${status}" 1
  assert_contains "${output}" "usage: artenv templates add-repo"
  run templates add-repo ribf file:///x extra
  assert_status "${status}" 1
  assert_contains "${output}" "usage: artenv templates add-repo"
  run templates add-repo ribf ""
  assert_status "${status}" 1
  assert_contains "${output}" "url must not be empty"
}

test_templates_group_help_lists_repo_cmds() {
  run templates --help
  assert_status "${status}" 0
  local c
  for c in add-repo remove-repo enable-repo disable-repo; do
    assert_contains "${output}" "${c}"
  done
}

test_top_level_help_mentions_repo_cmds() {
  run help
  assert_status "${status}" 0
  assert_contains "${output}" "add-repo"
}

test_add_repo_sigterm_during_fetch_rolls_back() {
  local fakebin="${ARTENV_ROOT}/.fixtures/fakebin"
  mkdir -p "${fakebin}"
  printf '#!/bin/sh\nexec sleep 30\n' > "${fakebin}/git"
  chmod +x "${fakebin}/git"
  local conf="${ARTENV_ROOT}/template-repos/slow.toml"
  # Own process group (like a terminal Ctrl-C) so the whole pipeline gets it.
  set -m
  PATH="${fakebin}:${PATH}" "${ARTENV_BIN}" templates add-repo slow "file:///x" >/dev/null 2>&1 &
  local pid=$!
  set +m
  for _ in $(seq 1 50); do
    [[ -e "${conf}" ]] && break
    sleep 0.1
  done
  assert_file "${conf}"
  sleep 0.3  # let the fetch start
  kill -TERM -- "-${pid}"
  local rc=0
  wait "${pid}" || rc=$?
  assert_status "${rc}" 130
  assert_no_file "${conf}"
  run templates add-repo slow "file:///x" --no-fetch
  assert_status "${status}" 0
}

test_enable_repo_matches_indented_enabled_key() {
  mkdir -p "${ARTENV_ROOT}/template-repos"
  printf '[repo]\nurl = "file:///x"\n  enabled = true\n' > "${ARTENV_ROOT}/template-repos/ind.toml"
  run templates disable-repo ind
  assert_status "${status}" 0
  [[ "$(grep -c 'enabled' "${ARTENV_ROOT}/template-repos/ind.toml")" -eq 1 ]] || fail "duplicate enabled key"
  [[ "$(toml_field "${ARTENV_ROOT}/template-repos/ind.toml" repo enabled)" == "false" ]] || fail "enabled should be false"
}

test_enable_repo_preserves_trailing_comment() {
  mkdir -p "${ARTENV_ROOT}/template-repos"
  printf '[repo]\nurl = "file:///x"\nenabled = false   # beamtime off\n' > "${ARTENV_ROOT}/template-repos/cm.toml"
  run templates enable-repo cm
  assert_status "${status}" 0
  assert_contains "$(cat "${ARTENV_ROOT}/template-repos/cm.toml")" "# beamtime off"
  [[ "$(toml_field "${ARTENV_ROOT}/template-repos/cm.toml" repo enabled)" == "true" ]] || fail "enabled should be true"
}

test_add_repo_help_ref_mentions_commit() {
  run templates add-repo --help
  assert_status "${status}" 0
  assert_contains "${output}" "Branch, tag or commit"
}
