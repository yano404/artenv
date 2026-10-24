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
  # Non-tty without -t dies (on a tty it would prompt to select a template).
  run new --multiuser "${ARTENV_ROOT}/proj"
  assert_status "${status}" 1
  assert_contains "${output}" "not a tty"
}

# --- 8: --repo without --multiuser ------------------------------------------

test_new_multiuser_repo_without_multiuser() {
  seed_cached_template
  run new "${ARTENV_ROOT}/proj" --repo "${ARTENV_ROOT}/up.git" -t myns/alpha
  assert_status "${status}" 1
  assert_contains "${output}" "only valid with --multiuser"
}

# --- 9: remote --repo (file:// URL, ssh, scp-like) ---------------------------

# Fake remote: an empty bare repo under the sandbox, addressed via file:// so
# dest_is_remote matches and git uses a real remote transport. No network.
make_fake_remote() { # [<head-branch>]
  git init -q --bare -b "${1:-main}" "${ARTENV_ROOT}/remote.git"
  printf 'file://%s/remote.git' "${ARTENV_ROOT}"
}

# Fake ssh: logs its args and fails, so no real network is ever touched.
make_fake_ssh() { # prints script path
  local f="${ARTENV_ROOT}/fake-ssh"
  printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s/ssh.log"\nexit 1\n' "${ARTENV_ROOT}" > "${f}"
  chmod +x "${f}"
  printf '%s' "${f}"
}

test_new_multiuser_remote_seeds_and_prints_register() {
  seed_cached_template
  local url
  url="$(make_fake_remote)"
  run new --multiuser "${ARTENV_ROOT}/proj" --repo "${url}" -t myns/alpha
  assert_status "${status}" 0
  assert_contains "${output}" "--repos ${url}"
  assert_contains "${output}" "--work ${ARTENV_ROOT}/proj"

  git clone -q -- "${url}" "${ARTENV_ROOT}/clone-r" 2>/dev/null
  [[ "$(cat "${ARTENV_ROOT}/clone-r/README")" == "hello" ]] || fail "expected cloned README to say hello"
  local n
  n="$(git -C "${ARTENV_ROOT}/clone-r" log --oneline | wc -l)"
  [[ "${n}" -eq 1 ]] || fail "expected exactly 1 commit, got ${n}"

  [[ -d "${ARTENV_ROOT}/proj" ]] || fail "expected dest dir to exist"
  [[ -z "$(ls -A "${ARTENV_ROOT}/proj")" ]] || fail "expected dest to be empty"
  [[ "$(stat -c '%a' "${ARTENV_ROOT}/proj")" == "2770" ]] || fail "expected mode 2770"
  assert_no_file "${ARTENV_ROOT}/proj/proj.git"
}

test_new_multiuser_remote_nonempty_refused() {
  seed_cached_template
  local url
  url="$(make_fake_remote)"
  git clone -q -- "${url}" "${ARTENV_ROOT}/pre" 2>/dev/null
  git -C "${ARTENV_ROOT}/pre" checkout -q -b other
  git -C "${ARTENV_ROOT}/pre" -c user.name=t -c user.email=t@t commit -q --allow-empty -m pre
  git -C "${ARTENV_ROOT}/pre" push -q -- "${url}" other
  local before after
  before="$(git ls-remote -- "${url}")"
  run new --multiuser "${ARTENV_ROOT}/proj" --repo "${url}" -t myns/alpha
  assert_status "${status}" 1
  assert_contains "${output}" "not empty"
  assert_contains "${output}" "artenv register"
  assert_no_file "${ARTENV_ROOT}/proj"
  after="$(git ls-remote -- "${url}")"
  [[ "${before}" == "${after}" ]] || fail "remote refs changed"
}

test_new_multiuser_remote_tag_only_refused() {
  seed_cached_template
  local url
  url="$(make_fake_remote)"
  git init -q -b main "${ARTENV_ROOT}/pre"
  git -C "${ARTENV_ROOT}/pre" -c user.name=t -c user.email=t@t commit -q --allow-empty -m pre
  git -C "${ARTENV_ROOT}/pre" tag v1
  git -C "${ARTENV_ROOT}/pre" push -q -- "${url}" v1
  run new --multiuser "${ARTENV_ROOT}/proj" --repo "${url}" -t myns/alpha
  assert_status "${status}" 1
  assert_contains "${output}" "not empty"
  assert_no_file "${ARTENV_ROOT}/proj"
}

test_new_multiuser_remote_unreachable() {
  seed_cached_template
  run new --multiuser "${ARTENV_ROOT}/proj" --repo "file://${ARTENV_ROOT}/nope.git" -t myns/alpha
  assert_status "${status}" 1
  assert_contains "${output}" "cannot access remote repository"
  assert_no_file "${ARTENV_ROOT}/proj"
}

test_new_multiuser_remote_push_rejected_cleans_up() {
  seed_cached_template
  local url
  url="$(make_fake_remote)"
  mkdir -p "${ARTENV_ROOT}/remote.git/hooks"
  printf '#!/bin/sh\nexit 1\n' > "${ARTENV_ROOT}/remote.git/hooks/pre-receive"
  chmod +x "${ARTENV_ROOT}/remote.git/hooks/pre-receive"
  run new --multiuser "${ARTENV_ROOT}/proj" --repo "${url}" -t myns/alpha
  assert_status "${status}" 1
  assert_contains "${output}" "failed to push"
  assert_no_file "${ARTENV_ROOT}/proj"
  [[ -z "$(git ls-remote -- "${url}")" ]] || fail "expected remote to remain empty"
}

test_new_multiuser_remote_seed_failure_cleans_up() {
  mkdir -p "${ARTENV_ROOT}/templates/myns/empty"
  local url
  url="$(make_fake_remote)"
  run new --multiuser "${ARTENV_ROOT}/proj" --repo "${url}" -t myns/empty
  assert_status "${status}" 1
  assert_contains "${output}" "failed to seed"
  assert_no_file "${ARTENV_ROOT}/proj"
  [[ -z "$(git ls-remote -- "${url}")" ]] || fail "expected remote to remain empty"
}

test_new_multiuser_remote_head_not_main_warns() {
  seed_cached_template
  local url
  url="$(make_fake_remote master)"
  run new --multiuser "${ARTENV_ROOT}/proj" --repo "${url}" -t myns/alpha
  assert_status "${status}" 0
  assert_contains "${output}" "default branch is not 'main'"
  git ls-remote --heads -- "${url}" | grep -q 'refs/heads/main' || fail "expected refs/heads/main on remote"
}

test_new_multiuser_remote_keeps_user_ssh_command() {
  seed_cached_template
  local fake
  fake="$(make_fake_ssh)"
  GIT_SSH_COMMAND="${fake} -o Foo=bar" run new --multiuser "${ARTENV_ROOT}/proj" --repo "ssh://example.invalid/x.git" -t myns/alpha
  assert_status "${status}" 1
  assert_contains "${output}" "cannot access remote repository"
  local log
  log="$(cat "${ARTENV_ROOT}/ssh.log")"
  assert_contains "${log}" "-o Foo=bar"
  assert_contains "${log}" "-o BatchMode=yes"
  assert_no_file "${ARTENV_ROOT}/proj"
}

test_new_multiuser_scp_like_url_is_remote() {
  seed_cached_template
  local fake
  fake="$(make_fake_ssh)"
  GIT_SSH_COMMAND="${fake}" run new --multiuser "${ARTENV_ROOT}/proj" --repo "git@example.invalid:x.git" -t myns/alpha
  assert_status "${status}" 1
  assert_contains "${output}" "cannot access remote repository"
  assert_no_file "${ARTENV_ROOT}/proj"
}

# host:path without a user (e.g. an ~/.ssh/config Host alias) is ssh to git, so
# it must take the remote path too -- not create a local dir and push blindly.
test_new_multiuser_host_alias_is_remote() {
  seed_cached_template
  cd "${ARTENV_ROOT}" || return 1
  local fake
  fake="$(make_fake_ssh)"
  GIT_SSH_COMMAND="${fake}" run new --multiuser "${ARTENV_ROOT}/proj" --repo "example-alias:x.git" -t myns/alpha
  assert_status "${status}" 1
  assert_contains "${output}" "cannot access remote repository"
  assert_no_file "${ARTENV_ROOT}/proj"
  assert_no_file "${ARTENV_ROOT}/example-alias:x.git"
}

# A local path containing ':' stays local when written as ./host:path (git's
# own rule: a '/' before the first ':' means a local path).
test_new_multiuser_dot_slash_colon_path_is_local() {
  seed_cached_template
  cd "${ARTENV_ROOT}" || return 1
  local fake
  fake="$(make_fake_ssh)"
  GIT_SSH_COMMAND="${fake}" run new --multiuser "${ARTENV_ROOT}/proj" --repo "./alias:x.git" -t myns/alpha
  assert_status "${status}" 0
  repo_has_main_local "${ARTENV_ROOT}/alias:x.git" || fail "expected a seeded local bare repo at ./alias:x.git"
  # relative --repo is resolved, so the printed register command is absolute
  assert_contains "${output}" "--repos ${ARTENV_ROOT}/alias:x.git"
  assert_no_file "${ARTENV_ROOT}/ssh.log"
}

repo_has_main_local() { git --git-dir="$1" rev-parse -q --verify refs/heads/main >/dev/null; }

# --repo inside a not-yet-created <dest> must work: the repo path cannot be
# canonicalised before <dest> exists.
test_new_multiuser_repo_inside_new_dest() {
  seed_cached_template
  run new --multiuser "${ARTENV_ROOT}/proj" --repo "${ARTENV_ROOT}/proj/custom.git" -t myns/alpha
  assert_status "${status}" 0
  repo_has_main_local "${ARTENV_ROOT}/proj/custom.git" || fail "expected a seeded bare repo at proj/custom.git"
  assert_contains "${output}" "--repos ${ARTENV_ROOT}/proj/custom.git"
}

# Same, with a relative --repo inside a not-yet-created <dest>.
test_new_multiuser_relative_repo_inside_new_dest() {
  seed_cached_template
  cd "${ARTENV_ROOT}" || return 1
  run new --multiuser "${ARTENV_ROOT}/proj" --repo "proj/custom.git" -t myns/alpha
  assert_status "${status}" 0
  repo_has_main_local "${ARTENV_ROOT}/proj/custom.git" || fail "expected a seeded bare repo at proj/custom.git"
  assert_contains "${output}" "--repos ${ARTENV_ROOT}/proj/custom.git"
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

# --- seed commit author identity ---------------------------------------------

test_new_multiuser_seed_author_is_user_identity() {
  seed_cached_template
  printf '[user]\n\tname = Alice Example\n\temail = alice@example.org\n' > "${ARTENV_ROOT}/.gitconfig-test"
  export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="${ARTENV_ROOT}/.gitconfig-test"
  run new --multiuser "${ARTENV_ROOT}/proj" -t myns/alpha
  assert_status "${status}" 0

  local author
  author="$(git -C "${ARTENV_ROOT}/proj/proj.git" log -1 --format='%an <%ae>' main)"
  [[ "${author}" == "Alice Example <alice@example.org>" ]] || fail "unexpected author: ${author}"
}

test_new_multiuser_seed_author_falls_back_to_artenv() {
  seed_cached_template
  : > "${ARTENV_ROOT}/.gitconfig-test"
  export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="${ARTENV_ROOT}/.gitconfig-test"
  run new --multiuser "${ARTENV_ROOT}/proj" -t myns/alpha
  assert_status "${status}" 0

  local author
  author="$(git -C "${ARTENV_ROOT}/proj/proj.git" log -1 --format='%an <%ae>' main)"
  [[ "${author}" == "artenv <artenv@localhost>" ]] || fail "unexpected author: ${author}"
}

test_new_help_mentions_remote_repo() {
  run new --help
  assert_status "${status}" 0
  assert_contains "${output}" "empty remote"
  assert_contains "${output}" "URL"
}
