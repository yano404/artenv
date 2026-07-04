#!/usr/bin/env bash
# shellcheck disable=SC2154  # status/output are set by run()/run_in() in lib.sh
# Tests for `artenv doctor --hygiene` (store-wide state hygiene scan).
# Each test runs in an isolated ARTENV_ROOT sandbox (see tests/lib.sh).

test_doctor_hygiene_clean() {
  apptainer_version_managed v1
  make_env good v1 true          # env -> v1, artlogin.sh present, use_artlogin=true

  run doctor --hygiene
  assert_status "${status}" 0
  assert_contains "${output}" "result: OK"
  assert_not_contains "${output}" "[NG]"
}

test_doctor_hygiene_empty_store() {
  # No versions, envs, or images: every section clean, exit 0.
  run doctor --hygiene
  assert_status "${status}" 0
  assert_contains "${output}" "result: OK"
}

test_doctor_hygiene_orphan_sif() {
  apptainer_version_managed v1              # images/v1.sif is referenced
  touch "${ARTENV_ROOT}/images/old.sif"     # leftover from a non-purged remove

  run doctor --hygiene
  assert_status "${status}" 1
  assert_contains "${output}" "orphan: ${ARTENV_ROOT}/images/old.sif"
  # The referenced image must not be flagged.
  assert_not_contains "${output}" "orphan: ${ARTENV_ROOT}/images/v1.sif"
}

test_doctor_hygiene_external_sif_not_flagged() {
  # A version whose SIF lives outside images/ must never be reported as orphan,
  # and images/ being empty means the section is clean.
  apptainer_version_external ext
  run doctor --hygiene
  assert_status "${status}" 0
  assert_contains "${output}" "orphan images"
  assert_not_contains "${output}" "[NG]"
}

test_doctor_hygiene_dangling_version() {
  make_env bad ghost                        # env -> version that does not exist

  run doctor --hygiene
  assert_status "${status}" 1
  assert_contains "${output}" "env 'bad' -> version 'ghost' (missing)"
}

test_doctor_hygiene_orphan_artlogin_no_env() {
  touch "${ARTENV_ROOT}/envs/stale.artlogin.sh"   # no matching envs/stale.toml

  run doctor --hygiene
  assert_status "${status}" 1
  assert_contains "${output}" "'stale.artlogin.sh': no matching env"
}

test_doctor_hygiene_artlogin_use_false() {
  # Env exists with use_artlogin=false, yet an artlogin.sh lingers.
  fake_native_version v1
  make_env e1 v1 false
  touch "${ARTENV_ROOT}/envs/e1.artlogin.sh"

  run doctor --hygiene
  assert_status "${status}" 1
  assert_contains "${output}" "'e1.artlogin.sh': env 'e1' has use_artlogin=false"
}

test_doctor_hygiene_help() {
  run doctor --help
  assert_status "${status}" 0
  assert_contains "${output}" "--hygiene"
}
