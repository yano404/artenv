#!/usr/bin/env bash
# shellcheck disable=SC2154  # status/output are set by run()/run_in() in lib.sh
# Tests for `artenv version info [<version>]`.

test_vinfo_native() {
  fake_native_version v1
  run version info v1
  assert_status "${status}" 0
  assert_contains "${output}" "- version: v1"
  assert_contains "${output}" "  - type: native"
  assert_contains "${output}" "  - artemis: /tmp/x/artemis"
  assert_contains "${output}" "  - yaml-cpp cmake: /tmp/x/yaml/cmake"
  # Non-existent paths are flagged [NG].
  assert_contains "${output}" "[NG]"
}

test_vinfo_apptainer_managed() {
  apptainer_version_managed v1          # image under images/ exists -> [OK]
  run version info v1
  assert_status "${status}" 0
  assert_contains "${output}" "  - type: apptainer"
  assert_contains "${output}" "${ARTENV_ROOT}/images/v1.sif [OK]"
  # Optional uri/digest are omitted when absent.
  assert_not_contains "${output}" "  - uri:"
  assert_not_contains "${output}" "  - digest:"
}

test_vinfo_apptainer_full() {
  apptainer_version_full v1             # carries uri + digest
  run version info v1
  assert_status "${status}" 0
  assert_contains "${output}" "  - uri: docker://example.org/artemis:v1"
  assert_contains "${output}" "  - digest: sha256:deadbeef"
}

test_vinfo_archived_suffix() {
  apptainer_version_managed v1
  printf 'archived = true\n' >> "${ARTENV_ROOT}/versions/v1.toml"
  run version info v1
  assert_status "${status}" 0
  assert_contains "${output}" "- version: v1 (archived)"
}

test_vinfo_bare_uses_art_version() {
  fake_native_version v1
  export ART_VERSION=v1
  run version info
  unset ART_VERSION
  assert_status "${status}" 0
  assert_contains "${output}" "- version: v1"
}

test_vinfo_missing() {
  run version info ghost
  assert_status "${status}" 1
  assert_contains "${output}" "version not found: ghost"
}

test_vinfo_no_arg_no_env() {
  run version info
  assert_status "${status}" 1
  assert_contains "${output}" "ART_VERSION is not set"
}

test_vinfo_too_many_args() {
  fake_native_version v1
  run version info v1 extra
  assert_status "${status}" 1
}

test_vinfo_help() {
  run version info --help
  assert_status "${status}" 0
  assert_contains "${output}" "artenv version info"
}

test_vinfo_not_in_commands() {
  run commands
  assert_not_contains "${output}" "version-info"
}
