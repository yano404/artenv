#!/usr/bin/env bash
# shellcheck disable=SC2154  # status/output are set by run()/run_in() in lib.sh
# Tests for deprecation notices emitted by the old-name shims.
# The notice goes to stderr only, is suppressible via ARTENV_NO_DEPRECATION,
# and never pollutes stdout (so piping the old names stays backward compatible).

# Every deprecated alias -> its canonical replacement (as the user types them).
_deprecated_map() {
  cat <<'MAP'
versions|version ls
remove-version|version remove
register-version|version register
archive-version|version archive
unarchive-version|version unarchive
install|version install
remove-env|remove
register-env|register
archive-env|archive
unarchive-env|unarchive
MAP
}

test_deprecation_all_shims_notify_stderr() {
  unset ARTENV_NO_DEPRECATION
  local old new err
  while IFS='|' read -r old new; do
    [[ -z "${old}" ]] && continue
    # -h keeps every canonical target fast and non-interactive; the shim
    # prints the notice before exec regardless of the forwarded args.
    err="$("${ARTENV_BIN}" "${old}" -h </dev/null 2>&1 >/dev/null)"
    assert_contains "${err}" "'artenv ${old}' is deprecated"
    assert_contains "${err}" "use 'artenv ${new}'"
  done < <(_deprecated_map)
}

test_deprecation_not_on_stdout() {
  unset ARTENV_NO_DEPRECATION
  fake_native_version foo
  local out
  # Canonical output is still delivered on stdout, without the notice.
  out="$("${ARTENV_BIN}" versions </dev/null 2>/dev/null)"
  assert_contains "${out}" "foo"
  assert_not_contains "${out}" "deprecated"
}

test_deprecation_suppressed_by_env() {
  export ARTENV_NO_DEPRECATION=1
  local err
  err="$("${ARTENV_BIN}" versions -h </dev/null 2>&1 >/dev/null)"
  assert_not_contains "${err}" "deprecated"
}

test_deprecation_canonical_names_have_no_notice() {
  unset ARTENV_NO_DEPRECATION
  # The grouped/env-implicit canonical forms must never warn.
  local err
  err="$("${ARTENV_BIN}" version ls -h </dev/null 2>&1 >/dev/null)"
  assert_not_contains "${err}" "deprecated"
  err="$("${ARTENV_BIN}" version install -h </dev/null 2>&1 >/dev/null)"
  assert_not_contains "${err}" "deprecated"
}
