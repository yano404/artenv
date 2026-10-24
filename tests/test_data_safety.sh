#!/usr/bin/env bash
# shellcheck disable=SC2154,SC2016  # status/output come from run()/run_in() in lib.sh; shell snippets are single-quoted on purpose
# Tests for: failures that must not lose data or be reported as success
# (migrate, version remove --purge, version install --update, the shell
# wrapper from `artenv init', and acd).

# --- migrate ------------------------------------------------------------------

test_migrate_converts_v1_version_and_env() {
  local v1="${ARTENV_ROOT}/versions/old" e1="${ARTENV_ROOT}/envs/e"
  mkdir -p "${v1}" "${e1}" "${ARTENV_ROOT}/x/work"
  local k
  for k in artsys rootsys yamllib yamlcmake; do
    mkdir -p "${ARTENV_ROOT}/x/${k}"
    ln -s "${ARTENV_ROOT}/x/${k}" "${v1}/${k}"
  done
  ln -s "${v1}" "${e1}/version"
  ln -s "${ARTENV_ROOT}/x/work" "${e1}/work"
  run migrate
  assert_status "${status}" 0
  assert_no_file "${v1}"
  assert_no_file "${e1}"
  [[ "$(toml_field "${ARTENV_ROOT}/versions/old.toml" version artsys)" == "${ARTENV_ROOT}/x/artsys" ]] \
    || fail "artsys not migrated"
  [[ "$(toml_field "${ARTENV_ROOT}/envs/e.toml" env version)" == "old" ]] || fail "env version not migrated"
}

test_migrate_unresolvable_link_keeps_original() {
  local v1="${ARTENV_ROOT}/versions/old"
  mkdir -p "${v1}"
  local k
  for k in artsys rootsys yamllib yamlcmake; do
    ln -s "/nonexistent-artenv-test/a/${k}" "${v1}/${k}"
  done
  run migrate
  assert_status "${status}" 1
  assert_contains "${output}" "cannot migrate version 'old'"
  [[ -d "${v1}" ]] || fail "v1 version dir was removed"
  assert_no_file "${ARTENV_ROOT}/versions/old.toml"
}

test_migrate_unresolvable_env_keeps_original() {
  local e1="${ARTENV_ROOT}/envs/e"
  mkdir -p "${e1}"
  ln -s "/nonexistent-artenv-test/a/v" "${e1}/version"
  ln -s "/nonexistent-artenv-test/a/w" "${e1}/work"
  run migrate
  assert_status "${status}" 1
  assert_contains "${output}" "cannot migrate env 'e'"
  [[ -d "${e1}" ]] || fail "v1 env dir was removed"
  assert_no_file "${ARTENV_ROOT}/envs/e.toml"
}

# --- version remove --purge -----------------------------------------------------

test_purge_keeps_sif_used_by_another_version() {
  touch "${ARTENV_ROOT}/images/shared.sif"
  local v
  for v in a b; do
    printf '[version]\ntype = "apptainer"\nimage = "%s"\n' \
      "${ARTENV_ROOT}/images/shared.sif" > "${ARTENV_ROOT}/versions/${v}.toml"
  done
  run version remove a --purge -y
  assert_status "${status}" 0
  assert_contains "${output}" "not removing image used by 'b'"
  assert_file "${ARTENV_ROOT}/images/shared.sif"
  assert_no_file "${ARTENV_ROOT}/versions/a.toml"
}

# --- version install --update ---------------------------------------------------

test_update_keeps_other_fields() {
  apptainer_version_full foo
  printf 'archived = true\n' >> "${ARTENV_ROOT}/versions/foo.toml"
  local bin="${ARTENV_ROOT}/fakebin"
  mkdir -p "${bin}"
  printf '#!/bin/sh\nexit 0\n' > "${bin}/apptainer"
  printf '#!/bin/sh\nexit 1\n' > "${bin}/curl"   # registry unreachable: no digest
  chmod +x "${bin}/apptainer" "${bin}/curl"
  PATH="${bin}:${PATH}" run_in $'y\n' version install --update foo
  assert_status "${status}" 0
  assert_contains "${output}" "foo was updated"
  local conf="${ARTENV_ROOT}/versions/foo.toml"
  [[ "$(toml_field "${conf}" version archived)" == "true" ]] || fail "archived lost: $(cat "${conf}")"
  [[ "$(toml_field "${conf}" version uri)" == "docker://example.org/artemis:foo" ]] || fail "uri lost"
  [[ -z "$(toml_field "${conf}" version digest)" ]] || fail "stale digest kept"
}

# --- shell wrapper / acd ------------------------------------------------------

test_shell_wrapper_propagates_failure() {
  run_shell_wrapper 'artenv shell no-such-env; echo "rc=$?"'
  assert_contains "${output}" "rc=1"
}

test_acd_handles_spaces_in_work_dir() {
  fake_native_version v1
  local work="${ARTENV_ROOT}/analysis 2026"
  mkdir -p "${work}"
  run register e --version v1 --work "${work}"
  assert_status "${status}" 0
  run_shell_wrapper 'artenv shell e >/dev/null
acd
echo "pwd=$PWD"'
  assert_contains "${output}" "pwd=${work}"
}

# Run <script> in a bash that has loaded `artenv init -', with aliases enabled.
run_shell_wrapper() { # <script>
  set +e
  output="$(PATH="${ARTENV_REPO}/bin:${PATH}" bash -c 'shopt -s expand_aliases
eval "$(artenv init -)"
'"$1" 2>&1)"
  status=$?
  set -e
}
