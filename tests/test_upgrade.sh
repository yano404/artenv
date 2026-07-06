#!/usr/bin/env bash
# shellcheck disable=SC2154  # status/output are set by run() in lib.sh
# Tests for: artenv upgrade (C6 self-update)
#
# `artenv upgrade` treats ARTENV_ROOT itself as the artenv git checkout (the
# real install layout: `$HOME/.artenv` IS the clone that `bin/artenv` was
# launched from). These tests never touch the real network: each case builds
# a throwaway local "remote" (a bare repo under $SANDBOX) plus an "upstream"
# working clone used only to push new commits/tags to that remote, then
# clones a fresh checkout and repoints ARTENV_ROOT at it. Everything lives
# under $SANDBOX, so teardown_sandbox's `rm -rf "$SANDBOX"` cleans it all up.

# Write a dummy, executable libexec/artenv---version reporting a fixed
# version string. This is the only file artenv-upgrade's version_of() reads
# from a checkout, so it's the minimal seed needed to observe before/after
# strings without a real artenv install tree.
_upgrade_write_version() { # <dir> <version>
  mkdir -p "$1/libexec"
  cat > "$1/libexec/artenv---version" <<EOF
#!/usr/bin/env bash
printf 'artenv %s\n' "$2"
EOF
  chmod +x "$1/libexec/artenv---version"
}

# Bare "remote" + an "upstream" working clone (used to push new releases) +
# a fresh "checkout" clone at v1.0.0 that becomes ARTENV_ROOT. Seeds the
# checkout's .gitignore to mirror the real repo's runtime-data ignores, so
# the "ignored files never block upgrade" case is realistic.
setup_upgrade_repo() {
  UPGRADE_UPSTREAM="${SANDBOX}/upstream_seed"
  UPGRADE_REMOTE="${SANDBOX}/remote.git"

  git init -q --bare -b main "${UPGRADE_REMOTE}"

  git init -q -b main "${UPGRADE_UPSTREAM}"
  git -C "${UPGRADE_UPSTREAM}" config user.email "tester@example.com"
  git -C "${UPGRADE_UPSTREAM}" config user.name "artenv tester"
  printf '/versions\n/envs\n/env\n/templates\n/template-repos\n/.claude\n' \
    > "${UPGRADE_UPSTREAM}/.gitignore"
  _upgrade_write_version "${UPGRADE_UPSTREAM}" "1.0.0"
  git -C "${UPGRADE_UPSTREAM}" add -A
  git -C "${UPGRADE_UPSTREAM}" commit -q -m "seed v1.0.0"
  git -C "${UPGRADE_UPSTREAM}" tag v1.0.0
  git -C "${UPGRADE_UPSTREAM}" remote add origin "${UPGRADE_REMOTE}"
  git -C "${UPGRADE_UPSTREAM}" push -q origin main --tags

  git clone -q "${UPGRADE_REMOTE}" "${SANDBOX}/checkout"
  git -C "${SANDBOX}/checkout" config user.email "tester@example.com"
  git -C "${SANDBOX}/checkout" config user.name "artenv tester"

  ARTENV_ROOT="${SANDBOX}/checkout"
  export ARTENV_ROOT
}

# Push a new release (version bump + tag) to the remote via the upstream
# clone. Call after setup_upgrade_repo.
bump_upgrade_release() { # <version> <tag>
  _upgrade_write_version "${UPGRADE_UPSTREAM}" "$1"
  git -C "${UPGRADE_UPSTREAM}" add -A
  git -C "${UPGRADE_UPSTREAM}" commit -q -m "release $2"
  git -C "${UPGRADE_UPSTREAM}" tag "$2"
  git -C "${UPGRADE_UPSTREAM}" push -q origin main --tags
}

# --- 1. update applied -------------------------------------------------

test_upgrade_applies_update() {
  setup_upgrade_repo
  local before_head
  before_head="$(git -C "${ARTENV_ROOT}" rev-parse HEAD)"
  bump_upgrade_release "1.1.0" "v1.1.0"

  run upgrade
  assert_status "${status}" 0
  assert_contains "${output}" "Upgraded artenv: artenv 1.0.0 -> artenv 1.1.0"

  local after_head tag_commit
  after_head="$(git -C "${ARTENV_ROOT}" rev-parse HEAD)"
  tag_commit="$(git -C "${ARTENV_ROOT}" rev-parse v1.1.0^{commit})"
  [[ "${after_head}" != "${before_head}" ]] || fail "HEAD did not move"
  [[ "${after_head}" == "${tag_commit}" ]] || fail "HEAD is not at v1.1.0 (got ${after_head}, want ${tag_commit})"
}

# --- 2. already up to date ----------------------------------------------

test_upgrade_already_up_to_date() {
  setup_upgrade_repo
  local before_head
  before_head="$(git -C "${ARTENV_ROOT}" rev-parse HEAD)"

  run upgrade
  assert_status "${status}" 0
  assert_contains "${output}" "Already up to date (artenv 1.0.0)"

  local after_head
  after_head="$(git -C "${ARTENV_ROOT}" rev-parse HEAD)"
  [[ "${after_head}" == "${before_head}" ]] || fail "HEAD moved on an up-to-date checkout"
}

# --- 3. downgrade guard ----------------------------------------------------

test_upgrade_downgrade_guard() {
  setup_upgrade_repo
  git -C "${ARTENV_ROOT}" commit -q --allow-empty -m "local dev commit ahead of any release"
  local before_head
  before_head="$(git -C "${ARTENV_ROOT}" rev-parse HEAD)"

  run upgrade
  assert_status "${status}" 0
  assert_contains "${output}" "Already at or ahead of the latest release (artenv 1.0.0); nothing to do"

  local after_head
  after_head="$(git -C "${ARTENV_ROOT}" rev-parse HEAD)"
  [[ "${after_head}" == "${before_head}" ]] || fail "downgrade guard failed to prevent HEAD from moving"
}

# --- 4. dirty guard ----------------------------------------------------

test_upgrade_dirty_worktree_blocks() {
  setup_upgrade_repo
  bump_upgrade_release "1.1.0" "v1.1.0"
  local before_head
  before_head="$(git -C "${ARTENV_ROOT}" rev-parse HEAD)"
  printf '# local edit\n' >> "${ARTENV_ROOT}/libexec/artenv---version"

  run upgrade
  assert_status "${status}" 1
  assert_contains "${output}" "you have local changes to tracked files"

  local after_head
  after_head="$(git -C "${ARTENV_ROOT}" rev-parse HEAD)"
  [[ "${after_head}" == "${before_head}" ]] || fail "HEAD moved despite a dirty worktree"
}

test_upgrade_dirty_staged_blocks() {
  setup_upgrade_repo
  bump_upgrade_release "1.1.0" "v1.1.0"
  local before_head
  before_head="$(git -C "${ARTENV_ROOT}" rev-parse HEAD)"
  printf '# local edit\n' >> "${ARTENV_ROOT}/libexec/artenv---version"
  git -C "${ARTENV_ROOT}" add -A

  run upgrade
  assert_status "${status}" 1
  assert_contains "${output}" "you have local changes to tracked files"

  local after_head
  after_head="$(git -C "${ARTENV_ROOT}" rev-parse HEAD)"
  [[ "${after_head}" == "${before_head}" ]] || fail "HEAD moved despite staged local changes"
}

# --- 5. gitignored runtime files never block ----------------------------

test_upgrade_ignores_gitignored_runtime_files() {
  setup_upgrade_repo
  bump_upgrade_release "1.1.0" "v1.1.0"
  mkdir -p "${ARTENV_ROOT}/versions" "${ARTENV_ROOT}/envs"
  touch "${ARTENV_ROOT}/versions/dummy.toml"
  printf 'default\n' > "${ARTENV_ROOT}/env"

  run upgrade
  assert_status "${status}" 0
  assert_contains "${output}" "Upgraded artenv: artenv 1.0.0 -> artenv 1.1.0"
  assert_file "${ARTENV_ROOT}/versions/dummy.toml"
  assert_file "${ARTENV_ROOT}/env"
}

# --- 6. preflight: not a git checkout -----------------------------------

test_upgrade_not_a_git_checkout() {
  # setup_sandbox already gave us a plain (non-git) ARTENV_ROOT.
  run upgrade
  assert_status "${status}" 1
  assert_contains "${output}" "is not a git checkout"
}

# --- 7. preflight: no remote configured ----------------------------------

test_upgrade_no_remote() {
  ARTENV_ROOT="${SANDBOX}/norepo"
  mkdir -p "${ARTENV_ROOT}"
  git init -q -b main "${ARTENV_ROOT}"
  git -C "${ARTENV_ROOT}" config user.email "tester@example.com"
  git -C "${ARTENV_ROOT}" config user.name "artenv tester"
  _upgrade_write_version "${ARTENV_ROOT}" "1.0.0"
  git -C "${ARTENV_ROOT}" add -A
  git -C "${ARTENV_ROOT}" commit -q -m "seed, no remote"
  export ARTENV_ROOT

  run upgrade
  assert_status "${status}" 1
  assert_contains "${output}" "no git remote configured"
}

# --- 8. remote has no release tags --------------------------------------

test_upgrade_no_tags_on_remote() {
  local upstream="${SANDBOX}/upstream_notags"
  local remote="${SANDBOX}/remote_notags.git"

  git init -q --bare -b main "${remote}"
  git init -q -b main "${upstream}"
  git -C "${upstream}" config user.email "tester@example.com"
  git -C "${upstream}" config user.name "artenv tester"
  _upgrade_write_version "${upstream}" "0.9.0"
  git -C "${upstream}" add -A
  git -C "${upstream}" commit -q -m "seed, no tags"
  git -C "${upstream}" remote add origin "${remote}"
  git -C "${upstream}" push -q origin main

  git clone -q "${remote}" "${SANDBOX}/checkout_notags"
  ARTENV_ROOT="${SANDBOX}/checkout_notags"
  export ARTENV_ROOT

  run upgrade
  assert_status "${status}" 1
  assert_contains "${output}" "no release tags found"
}

# --- 9. -h / --help (flags parsed before any git access) -----------------

test_upgrade_help() {
  run upgrade -h
  assert_status "${status}" 0
  assert_contains "${output}" "usage: artenv upgrade"
  assert_contains "${output}" "--help"

  run upgrade --help
  assert_status "${status}" 0
  assert_contains "${output}" "usage: artenv upgrade"
}

# --- 10. unknown option ---------------------------------------------------

test_upgrade_unknown_option() {
  run upgrade --bogus
  assert_status "${status}" 1
  assert_contains "${output}" "unknown option: --bogus"
}

# --- 11. unexpected positional argument -----------------------------------

test_upgrade_unexpected_argument() {
  run upgrade foo
  assert_status "${status}" 1
  assert_contains "${output}" "unexpected argument: foo"
  assert_contains "${output}" "usage: artenv upgrade"
}
