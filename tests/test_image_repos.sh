#!/usr/bin/env bash
# Image repositories: seed, `version repos`, `version add-repo`.

test_repos_seeds_default() {
  seed_share_image_default
  run version repos
  assert_status "${status}" 0
  assert_contains "${output}" "default"
  assert_contains "${output}" "ghcr.io/yano404/artemis_apptainer"
  assert_file "${ARTENV_ROOT}/image-repos/default.toml"
}

test_repos_keeps_deleted_default_deleted() {
  seed_share_image_default
  mkdir "${ARTENV_ROOT}/image-repos"
  run version repos
  assert_status "${status}" 0
  assert_not_contains "${output}" "default"
  assert_no_file "${ARTENV_ROOT}/image-repos/default.toml"
}

test_add_repo_registers_existing_image() {
  use_fake_ghcr
  fake_ghcr_image ghcr.io/yano404/artemis-g4_apptainer v1
  run version add-repo g4 ghcr.io/yano404/artemis-g4_apptainer --description "Artemis + Geant4"
  assert_status "${status}" 0
  assert_contains "${output}" "added g4"
  [[ "$(toml_field "${ARTENV_ROOT}/image-repos/g4.toml" repo image)" == "ghcr.io/yano404/artemis-g4_apptainer" ]] \
    || fail "image not stored"
  [[ "$(toml_field "${ARTENV_ROOT}/image-repos/g4.toml" repo description)" == "Artemis + Geant4" ]] \
    || fail "description not stored"
  run version repos
  assert_contains "${output}" "g4"
  assert_contains "${output}" "Artemis + Geant4"
}

test_add_repo_empty_tag_list_ok() {
  use_fake_ghcr
  fake_ghcr_image ghcr.io/yano404/empty_img
  run version add-repo e ghcr.io/yano404/empty_img
  assert_status "${status}" 0
  assert_file "${ARTENV_ROOT}/image-repos/e.toml"
}

test_add_repo_unreachable_not_registered() {
  use_fake_ghcr
  run version add-repo g4 ghcr.io/yano404/nonexistent
  assert_status "${status}" 1
  assert_contains "${output}" "could not"
  assert_no_file "${ARTENV_ROOT}/image-repos/g4.toml"
}

test_add_repo_rejects_bad_images() {
  use_fake_ghcr
  fake_ghcr_image ghcr.io/x/y v1
  local img
  for img in ghcr.io/x/y:tag ghcr.io/x/y@sha256:abc oras://ghcr.io/x/y docker.io/x/y ghcr.io/x ghcr.io/x/../y; do
    run version add-repo g4 "${img}"
    assert_status "${status}" 1 "(${img})"
    assert_contains "${output}" "public ghcr.io image path"
    assert_no_file "${ARTENV_ROOT}/image-repos/g4.toml"
  done
}

test_add_repo_existing_name_refused() {
  use_fake_ghcr
  fake_ghcr_image ghcr.io/x/y v1
  fake_ghcr_image ghcr.io/x/z v1
  run version add-repo g4 ghcr.io/x/y
  assert_status "${status}" 0
  run version add-repo g4 ghcr.io/x/z
  assert_status "${status}" 1
  assert_contains "${output}" "already exists"
  [[ "$(toml_field "${ARTENV_ROOT}/image-repos/g4.toml" repo image)" == "ghcr.io/x/y" ]] \
    || fail "first conf changed"
}

test_add_repo_bad_name() {
  use_fake_ghcr
  fake_ghcr_image ghcr.io/x/y v1
  local n
  for n in .x a/b; do
    run version add-repo "${n}" ghcr.io/x/y
    assert_status "${status}" 1 "(${n})"
    assert_contains "${output}" "invalid repository name"
  done
  # A leading `-' is taken as an option, so it never becomes a name.
  run version add-repo -x ghcr.io/x/y
  assert_status "${status}" 1
  assert_contains "${output}" "unknown option"
}

test_add_repo_quotes_description() {
  use_fake_ghcr
  fake_ghcr_image ghcr.io/x/y v1
  run version add-repo q ghcr.io/x/y --description 'say "hi" \ there'
  assert_status "${status}" 0
  [[ "$(toml_field "${ARTENV_ROOT}/image-repos/q.toml" repo description)" == 'say "hi" \ there' ]] \
    || fail "description did not round-trip"
}
