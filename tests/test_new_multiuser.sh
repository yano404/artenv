#!/usr/bin/env bash
# shellcheck disable=SC2154  # status/output are set by run()/run_in() in lib.sh
# Regression tests for `artenv new --multiuser <dest> [--repo <repo>] -t <template>`
# (the two-step multiuser skeleton: create_shared_dir + bootstrap_shared_repo in
# libexec/util.sh, driven from libexec/artenv-new). This mode is fully
# flag-driven and never prompts, so it needs no pty/stdin tricks like the
# single-user `select` path.
#
# Fixture: a "cached" template with NO .git entry (mirrors a real
# templates/<ns>/<name> tree after `templates update` strips VCS metadata).
seed_cached_template() {
  mkdir -p "${ARTENV_ROOT}/templates/myns/alpha"
  printf 'hello\n' > "${ARTENV_ROOT}/templates/myns/alpha/README"
}

# A template that (incorrectly) still carries a .git dir, to exercise the
# bootstrap_shared_repo guard.
seed_template_with_git() {
  mkdir -p "${ARTENV_ROOT}/templates/myns/bad/.git"
  printf 'x\n' > "${ARTENV_ROOT}/templates/myns/bad/README"
}

# mode & no-world-access assertion: expects exactly setgid + group rwx, no
# world bits (i.e. octal mode 2770).
assert_setgid_group_writable() {
  local p
  p="$(stat -c '%a' "$1")"
  (( (0"${p}" & 02000) != 0 )) || fail "expected setgid on $1 (mode ${p})"
  (( (0"${p}" & 00020) != 0 )) || fail "expected group-write on $1 (mode ${p})"
}

assert_no_world_access() {
  local p world
  p="$(stat -c '%a' "$1")"
  world="${p: -1}"
  [[ "${world}" == "0" ]] || fail "expected no world access on $1 (mode ${p})"
}

# --- 1: dest created empty + 2770, template does NOT land in dest -----------

test_new_multiuser_dest_created_empty_and_2770() {
  seed_cached_template
  run new --multiuser "${ARTENV_ROOT}/proj" -t myns/alpha
  assert_status "${status}" 0
  [[ -d "${ARTENV_ROOT}/proj" ]] || fail "expected dest dir to exist"
  assert_setgid_group_writable "${ARTENV_ROOT}/proj"
  assert_no_world_access "${ARTENV_ROOT}/proj"
  local mode
  mode="$(stat -c '%a' "${ARTENV_ROOT}/proj")"
  [[ "${mode}" == "2770" ]] || fail "expected mode 2770, got ${mode}"

  local -a entries=()
  mapfile -t entries < <(ls -A "${ARTENV_ROOT}/proj")
  [[ "${#entries[@]}" -eq 1 && "${entries[0]}" == "proj.git" ]] \
    || fail "expected dest to contain only proj.git, got: ${entries[*]}"
}

# --- 2: repo is a --shared=group bare repo on main --------------------------

test_new_multiuser_repo_is_shared_bare_on_main() {
  seed_cached_template
  run new --multiuser "${ARTENV_ROOT}/proj" -t myns/alpha
  assert_status "${status}" 0

  local repo="${ARTENV_ROOT}/proj/proj.git"
  [[ "$(git -C "${repo}" rev-parse --is-bare-repository)" == "true" ]] \
    || fail "expected bare repository at ${repo}"

  local shared
  shared="$(git -C "${repo}" config core.sharedRepository)"
  case "${shared}" in
    group|1|true) : ;;
    *) fail "expected core.sharedRepository in {group,1,true}, got: ${shared}" ;;
  esac

  git ls-remote --heads -- "${repo}" | grep -q 'refs/heads/main' \
    || fail "expected refs/heads/main in ls-remote output"
}

# --- 3: clone yields template contents + exactly one Seed commit -----------

test_new_multiuser_clone_yields_template_and_one_seed_commit() {
  seed_cached_template
  run new --multiuser "${ARTENV_ROOT}/proj" -t myns/alpha
  assert_status "${status}" 0

  local clone_dir="${ARTENV_ROOT}/clone-c"
  git clone -q -- "${ARTENV_ROOT}/proj/proj.git" "${clone_dir}"
  [[ "$(cat "${clone_dir}/README")" == "hello" ]] || fail "expected cloned README to say hello"

  local n_commits first_msg
  n_commits="$(git -C "${clone_dir}" log --oneline | wc -l)"
  [[ "${n_commits}" -eq 1 ]] || fail "expected exactly 1 commit, got ${n_commits}"
  first_msg="$(git -C "${clone_dir}" log --oneline -1)"
  [[ "${first_msg}" == *"Seed from template"* ]] || fail "expected commit message to start with 'Seed from template', got: ${first_msg}"
}

# --- 4: default repo path is <dest>/<basename>.git --------------------------

test_new_multiuser_default_repo_path() {
  seed_cached_template
  run new --multiuser "${ARTENV_ROOT}/proj" -t myns/alpha
  assert_status "${status}" 0
  [[ -d "${ARTENV_ROOT}/proj/proj.git" ]] || fail "expected default repo at proj/proj.git"
  assert_contains "${output}" "${ARTENV_ROOT}/proj/proj.git"
}

# --- 5: explicit --repo honored, lives outside dest -------------------------

test_new_multiuser_explicit_repo_outside_dest() {
  seed_cached_template
  run new --multiuser "${ARTENV_ROOT}/proj" --repo "${ARTENV_ROOT}/up.git" -t myns/alpha
  assert_status "${status}" 0

  [[ -d "${ARTENV_ROOT}/up.git" ]] || fail "expected repo at explicit --repo path"
  [[ "$(git -C "${ARTENV_ROOT}/up.git" rev-parse --is-bare-repository)" == "true" ]] \
    || fail "expected bare repo at explicit --repo path"

  local -a entries=()
  mapfile -t entries < <(ls -A "${ARTENV_ROOT}/proj")
  [[ "${#entries[@]}" -eq 0 ]] || fail "expected dest to have no repo inside it, got: ${entries[*]}"
}

# --- 6: positional dest missing ---------------------------------------------

test_new_multiuser_missing_dest() {
  seed_cached_template
  run new --multiuser -t myns/alpha
  assert_status "${status}" 1
  assert_contains "${output}" "requires a shared directory"
}

# --- 7: -t missing -----------------------------------------------------------

test_new_multiuser_missing_template() {
  run new --multiuser "${ARTENV_ROOT}/proj"
  assert_status "${status}" 1
  assert_contains "${output}" "requires -t"
}

# --- 8: --repo without --multiuser ------------------------------------------

test_new_multiuser_repo_without_multiuser() {
  seed_cached_template
  run new "${ARTENV_ROOT}/proj" --repo "${ARTENV_ROOT}/up.git" -t myns/alpha
  assert_status "${status}" 1
  assert_contains "${output}" "only valid with --multiuser"
}

# --- 9: remote --repo (URL and scp-like) are rejected -----------------------

test_new_multiuser_repo_url_rejected() {
  seed_cached_template
  run new --multiuser "${ARTENV_ROOT}/proj" --repo "https://example.com/x.git" -t myns/alpha
  assert_status "${status}" 1
  assert_contains "${output}" "not yet supported"
}

test_new_multiuser_repo_scp_like_rejected() {
  seed_cached_template
  run new --multiuser "${ARTENV_ROOT}/proj" --repo "git@host:x.git" -t myns/alpha
  assert_status "${status}" 1
  assert_contains "${output}" "not yet supported"
}

# --- 10: non-empty dest dies, nothing is created/removed --------------------

test_new_multiuser_nonempty_dest_dies_untouched() {
  seed_cached_template
  mkdir -p "${ARTENV_ROOT}/proj"
  printf 'keepme\n' > "${ARTENV_ROOT}/proj/existing.txt"

  run new --multiuser "${ARTENV_ROOT}/proj" -t myns/alpha
  assert_status "${status}" 1
  assert_contains "${output}" "not empty"

  assert_file "${ARTENV_ROOT}/proj/existing.txt"
  [[ "$(cat "${ARTENV_ROOT}/proj/existing.txt")" == "keepme" ]] || fail "expected pre-existing file preserved"
  assert_no_file "${ARTENV_ROOT}/proj/proj.git"
}

# --- 11: guardrail output ----------------------------------------------------

test_new_multiuser_guardrail_output() {
  seed_cached_template
  run new --multiuser "${ARTENV_ROOT}/proj" -t myns/alpha
  assert_status "${status}" 0
  assert_contains "${output}" "artenv register"
  assert_contains "${output}" "--work ${ARTENV_ROOT}/proj"
  assert_contains "${output}" "--repos ${ARTENV_ROOT}/proj/proj.git"
  assert_contains "${output}" "--multiuser"
  assert_contains "${output}" "${ARTENV_ROOT}/proj"
  assert_contains "${output}" "${ARTENV_ROOT}/proj/proj.git"
}

# --- 12: no env is registered ------------------------------------------------

test_new_multiuser_does_not_register_env() {
  seed_cached_template
  run new --multiuser "${ARTENV_ROOT}/proj" -t myns/alpha
  assert_status "${status}" 0

  local -a env_files=()
  shopt -s nullglob
  env_files=("${ARTENV_ROOT}/envs"/*.toml "${ARTENV_ROOT}/envs"/*.artlogin.sh)
  shopt -u nullglob
  [[ "${#env_files[@]}" -eq 0 ]] || fail "expected no env artifacts, found: ${env_files[*]}"
}

# --- 13: template containing .git is rejected, self-created dest removed ---

test_new_multiuser_template_with_git_guard() {
  seed_template_with_git
  run new --multiuser "${ARTENV_ROOT}/proj" -t myns/bad
  assert_status "${status}" 1
  assert_contains "${output}" "must not contain a .git"
  assert_no_file "${ARTENV_ROOT}/proj"
}

# --- 14: bootstrap failure after dest creation cleans up self-created dest --
#
# NOTE: pre-creating the *default* repo path (dest/basename.git) as a
# non-empty dir does NOT reach bootstrap_shared_repo's own repo-empty check —
# it makes `dest` itself pre-exist and non-empty, so create_shared_dir's own
# emptiness check dies first (verified empirically), and since the dest then
# counts as pre-existing, the trap intentionally leaves it in place (same
# code path as test #10, just with a proj.git entry instead of a plain
# file). To genuinely exercise bootstrap_shared_repo's repo-not-empty probe
# *after* create_shared_dir has already made a fresh (self-created, still
# empty) dest, the repo must live outside dest via --repo: dest starts
# absent (so it is self-created and owned by the EXIT trap), while the
# --repo target is pre-created non-empty so the bootstrap step fails.

test_new_multiuser_bootstrap_failure_cleans_up_dest() {
  seed_cached_template
  mkdir -p "${ARTENV_ROOT}/up.git"
  touch "${ARTENV_ROOT}/up.git/not-empty"

  run new --multiuser "${ARTENV_ROOT}/proj" --repo "${ARTENV_ROOT}/up.git" -t myns/alpha
  assert_status "${status}" 1
  assert_contains "${output}" "not empty"

  # dest was never pre-existing, so it is self-created/owned -> removed on
  # failure by the EXIT trap.
  assert_no_file "${ARTENV_ROOT}/proj"
  # The pre-existing --repo target itself is NOT owned by the trap (it was
  # never successfully bootstrapped) and is left untouched.
  assert_file "${ARTENV_ROOT}/up.git/not-empty"
}

# A sibling case matching the task's literal repro: pre-creating the
# *default* repo path makes `dest` itself pre-exist and non-empty, so
# create_shared_dir's own check fires first and (by design) the pre-existing
# dest is preserved rather than removed.
test_new_multiuser_default_repo_precreated_makes_dest_preexist() {
  seed_cached_template
  mkdir -p "${ARTENV_ROOT}/proj/proj.git"
  touch "${ARTENV_ROOT}/proj/proj.git/not-empty"

  run new --multiuser "${ARTENV_ROOT}/proj" -t myns/alpha
  assert_status "${status}" 1
  assert_contains "${output}" "not empty"

  # Pre-existing dest is preserved (not removed) per the documented cleanup
  # discipline: only a self-created dest is owned by the EXIT trap.
  assert_file "${ARTENV_ROOT}/proj/proj.git/not-empty"
}
