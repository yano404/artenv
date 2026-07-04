#!/usr/bin/env bash
# shellcheck disable=SC2154  # status/output are set by run()/run_in() in lib.sh
# Tests for: C1 "template seed" — default.toml is a tracked seed under
# share/template-repos/, and ensure_default_repo() (libexec/util.sh) copies it
# into the runtime ${ARTENV_ROOT}/template-repos/ dir only on first use.
#
# The sandbox (tests/lib.sh setup_sandbox) never has a share/ dir, so
# ensure_default_repo is a no-op there by construction; every test below that
# wants to exercise the seeding path must create the sandbox seed itself via
# seed_share_default.

seed_share_default() {
  mkdir -p "${ARTENV_ROOT}/share/template-repos"
  printf '[repo]\nurl = "https://example.com/x.git"\nenabled = true\ndescription = "seed"\n' \
    > "${ARTENV_ROOT}/share/template-repos/default.toml"
}

# --- seeding on first use -----------------------------------------------

test_template_seed_fresh_store_seeds_default() {
  seed_share_default
  run templates repos
  assert_status "${status}" 0
  assert_file "${ARTENV_ROOT}/template-repos/default.toml"
  assert_contains "${output}" "default"
}

test_template_seed_ls_reflects_seeded_default() {
  seed_share_default
  run templates ls
  assert_status "${status}" 0
  # No repo has been `templates update`d yet, so the cold-start hint fires
  # for the (now-seeded) enabled `default' repo.
  assert_contains "${output}" "artenv templates update"

  run templates repos
  assert_status "${status}" 0
  assert_contains "${output}" "default"
  assert_contains "${output}" "https://example.com/x.git"
  assert_contains "${output}" "true"
}

# --- existing default.toml is never overwritten -------------------------

test_template_seed_does_not_overwrite_existing_default() {
  mkdir -p "${ARTENV_ROOT}/template-repos"
  printf '[repo]\nurl = "https://sentinel.example/keep.git"\nenabled = true\ndescription = "sentinel"\n' \
    > "${ARTENV_ROOT}/template-repos/default.toml"
  seed_share_default

  run templates repos
  assert_status "${status}" 0
  assert_contains "$(cat "${ARTENV_ROOT}/template-repos/default.toml")" "sentinel"
  assert_not_contains "$(cat "${ARTENV_ROOT}/template-repos/default.toml")" "example.com/x.git"
}

# --- deleted default.toml is never resurrected --------------------------

test_template_seed_deleted_default_not_resurrected() {
  seed_share_default
  mkdir -p "${ARTENV_ROOT}/template-repos"   # dir present, default.toml absent (user removed it)

  run templates repos
  assert_status "${status}" 0
  assert_no_file "${ARTENV_ROOT}/template-repos/default.toml"
}

# --- no seed present: clean no-op ----------------------------------------

test_template_seed_no_seed_is_clean_noop() {
  # No share/ dir at all (the normal sandbox state).
  run templates repos
  assert_status "${status}" 0
  assert_no_file "${ARTENV_ROOT}/template-repos/default.toml"
  assert_no_file "${ARTENV_ROOT}/template-repos"
}

test_template_seed_no_seed_ls_still_works() {
  run templates ls
  assert_status "${status}" 0
  assert_no_file "${ARTENV_ROOT}/template-repos"
}

# --- init best-effort seeding ---------------------------------------------

test_template_seed_init_seeds_default() {
  seed_share_default
  run init -
  assert_status "${status}" 0
  assert_file "${ARTENV_ROOT}/template-repos/default.toml"
  assert_contains "${output}" "artenv() {"
}

test_template_seed_init_no_seed_no_dir_no_stdout_pollution() {
  run init -
  assert_status "${status}" 0
  assert_contains "${output}" "artenv() {"
  assert_no_file "${ARTENV_ROOT}/template-repos"
}
