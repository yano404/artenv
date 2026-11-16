#!/usr/bin/env bash
# shellcheck disable=SC2154  # status/output are globals set by run() in lib.sh
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

# --- remove-repo / edit-repo -----------------------------------------------

test_remove_repo_deletes_conf_only() {
  use_fake_ghcr
  fake_ghcr_image ghcr.io/yano404/artemis-g4_apptainer v1
  run version add-repo g4 ghcr.io/yano404/artemis-g4_apptainer
  assert_status "${status}" 0
  local vt="${ARTENV_ROOT}/versions/artemis-g4_apptainer-v1.toml"
  mkdir -p "${ARTENV_ROOT}/versions"
  cat > "${vt}" <<'EOT'
[version]
type = "apptainer"
uri = "oras://ghcr.io/yano404/artemis-g4_apptainer:v1"
EOT
  local before
  before="$(cat "${vt}")"
  run version remove-repo g4
  assert_status "${status}" 0
  assert_contains "${output}" "removed"
  assert_no_file "${ARTENV_ROOT}/image-repos/g4.toml"
  [[ "$(cat "${vt}")" == "${before}" ]] || fail "version toml changed"
}

test_remove_repo_default_allowed() {
  seed_share_image_default
  run version repos
  assert_contains "${output}" "default"
  run version remove-repo default
  assert_status "${status}" 0
  assert_no_file "${ARTENV_ROOT}/image-repos/default.toml"
  run version repos
  assert_status "${status}" 0
  assert_not_contains "${output}" "default"
}

test_remove_repo_unknown() {
  seed_share_image_default
  run version remove-repo nosuch
  assert_status "${status}" 1
  assert_contains "${output}" "no such image repository"
}

test_edit_repo_uses_editor() {
  seed_share_image_default
  local ed="${ARTENV_ROOT}/ed.sh"
  cat > "${ed}" <<'EOT'
#!/usr/bin/env bash
sed -i 's/^description *= .*/description = "edited desc"/' "$1"
EOT
  chmod +x "${ed}"
  EDITOR="${ed}" run version edit-repo default
  assert_status "${status}" 0
  [[ "$(toml_field "${ARTENV_ROOT}/image-repos/default.toml" repo description)" == "edited desc" ]] \
    || fail "description not updated"
}

test_edit_repo_invalid_image_reported() {
  seed_share_image_default
  local ed="${ARTENV_ROOT}/ed.sh"
  cat > "${ed}" <<'EOT'
#!/usr/bin/env bash
sed -i 's|^image *= .*|image = "docker.io/x/y"|' "$1"
EOT
  chmod +x "${ed}"
  EDITOR="${ed}" run version edit-repo default
  assert_status "${status}" 1
  assert_contains "${output}" "public ghcr.io image path"
  assert_file "${ARTENV_ROOT}/image-repos/default.toml"
}

# --- install / list from registered repositories ---------------------------

# Fake `apptainer` on PATH: logs its args, creates the destination SIF.
use_fake_apptainer() {
  mkdir -p "${ARTENV_ROOT}/.fake-bin"
  cat > "${ARTENV_ROOT}/.fake-bin/apptainer" <<'EOS'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${ARTENV_ROOT}/apptainer.log"
shift
[[ "${1:-}" == "--force" ]] && shift
mkdir -p -- "$(dirname -- "$1")"
: > "$1"
EOS
  chmod +x "${ARTENV_ROOT}/.fake-bin/apptainer"
  export PATH="${ARTENV_ROOT}/.fake-bin:${PATH}"
}

test_install_default_unchanged() {
  seed_share_image_default
  use_fake_ghcr
  use_fake_apptainer
  fake_ghcr_image ghcr.io/yano404/artemis_apptainer v1
  run_in $'y\n' version install v1
  assert_status "${status}" 0
  local conf="${ARTENV_ROOT}/versions/artemis_apptainer-v1.toml"
  assert_file "${conf}"
  [[ "$(toml_field "${conf}" version uri)" == "oras://ghcr.io/yano404/artemis_apptainer:v1" ]] \
    || fail "uri wrong"
  assert_contains "$(cat "${ARTENV_ROOT}/apptainer.log")" "oras://ghcr.io/yano404/artemis_apptainer:v1"
}

test_install_from_named_repo() {
  seed_share_image_default
  use_fake_ghcr
  use_fake_apptainer
  fake_ghcr_image ghcr.io/yano404/artemis-g4_apptainer v1.2.3-g4.11.2
  run version add-repo g4 ghcr.io/yano404/artemis-g4_apptainer
  assert_status "${status}" 0
  run_in $'y\n' version install g4/v1.2.3-g4.11.2
  assert_status "${status}" 0
  local conf="${ARTENV_ROOT}/versions/artemis-g4_apptainer-v1.2.3-g4.11.2.toml"
  assert_file "${conf}"
  [[ "$(toml_field "${conf}" version uri)" == "oras://ghcr.io/yano404/artemis-g4_apptainer:v1.2.3-g4.11.2" ]] \
    || fail "uri wrong"
}

test_install_without_default() {
  seed_share_image_default
  use_fake_ghcr
  use_fake_apptainer
  fake_ghcr_image ghcr.io/yano404/artemis-g4_apptainer v1
  run version add-repo g4 ghcr.io/yano404/artemis-g4_apptainer
  rm -f "${ARTENV_ROOT}/image-repos/default.toml"
  run_in $'y\n' version install v1
  assert_status "${status}" 1
  assert_contains "${output}" "no such image repository: default"
  run_in $'y\n' version install g4/v1
  assert_status "${status}" 0
}

test_install_unknown_repo() {
  seed_share_image_default
  use_fake_apptainer
  run_in $'y\n' version install nope/v1
  assert_status "${status}" 1
  assert_contains "${output}" "no such image repository: nope"
}

test_install_collision_hint() {
  seed_share_image_default
  use_fake_apptainer
  mkdir -p "${ARTENV_ROOT}/versions"
  printf '[version]\ntype = "native"\n' > "${ARTENV_ROOT}/versions/artemis_apptainer-v1.toml"
  run_in $'y\n' version install v1
  assert_status "${status}" 1
  assert_contains "${output}" "without a tag"
}

test_install_interactive_selects_repo() {
  seed_share_image_default
  use_fake_ghcr
  use_fake_apptainer
  fake_ghcr_image ghcr.io/yano404/artemis-g4_apptainer v1
  run version add-repo g4 ghcr.io/yano404/artemis-g4_apptainer
  # repos sorted: default, g4 -> choose 2; accept URI default, name, SIF default
  run_in $'2\n\nmyver\n\ny\n' version install
  assert_status "${status}" 0
  assert_contains "${output}" "oras://ghcr.io/yano404/artemis-g4_apptainer:latest"
  assert_file "${ARTENV_ROOT}/versions/myver.toml"
}

test_install_interactive_no_repos() {
  seed_share_image_default
  use_fake_apptainer
  mkdir "${ARTENV_ROOT}/image-repos"
  run_in '' version install
  assert_status "${status}" 1
  assert_contains "${output}" "version add-repo"
}

test_list_all_repos_grouped() {
  seed_share_image_default
  use_fake_ghcr
  fake_ghcr_image ghcr.io/yano404/artemis_apptainer v1 latest=sha256:v1
  fake_ghcr_image ghcr.io/yano404/artemis-g4_apptainer v2
  run version add-repo g4 ghcr.io/yano404/artemis-g4_apptainer
  run version install --list
  assert_status "${status}" 0
  assert_contains "${output}" "default (ghcr.io/yano404/artemis_apptainer)"
  assert_contains "${output}" "v1 -> latest"
  assert_contains "${output}" "g4 (ghcr.io/yano404/artemis-g4_apptainer)"
  assert_contains "${output}" "v2"
}

test_list_one_repo() {
  seed_share_image_default
  use_fake_ghcr
  fake_ghcr_image ghcr.io/yano404/artemis_apptainer v1
  fake_ghcr_image ghcr.io/yano404/artemis-g4_apptainer v2
  run version add-repo g4 ghcr.io/yano404/artemis-g4_apptainer
  run version install --list g4
  assert_status "${status}" 0
  assert_contains "${output}" "g4 ("
  assert_not_contains "${output}" "default ("
}

test_list_partial_failure() {
  seed_share_image_default
  use_fake_ghcr
  fake_ghcr_image ghcr.io/yano404/artemis_apptainer v1
  run version repos   # seeds image-repos/
  printf '[repo]\nimage = "ghcr.io/yano404/unknown_img"\n' > "${ARTENV_ROOT}/image-repos/g4.toml"
  run version install --list
  assert_status "${status}" 1
  assert_contains "${output}" "default (ghcr.io/yano404/artemis_apptainer)"
  assert_contains "${output}" "v1"
  assert_contains "${output}" "cannot list g4"
}

test_list_no_repos() {
  seed_share_image_default
  use_fake_ghcr
  mkdir "${ARTENV_ROOT}/image-repos"
  run version install --list
  assert_status "${status}" 1
  assert_contains "${output}" "version add-repo"
}
