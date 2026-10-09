#!/usr/bin/env bash
# shellcheck disable=SC2154  # status/output are set by run()/run_in() in lib.sh
# Tests which commands `artenv shell` wraps for Apptainer environments (#64).
# EMIT-level: they check the shell code sh-shell prints, not the container
# runtime. Only artemis/root are wrapped; builds go through artexec, and
# make/cmake are never touched.

test_apptainer_wraps_artemis_root_and_artexec() {
  apptainer_version_managed appv
  make_env myapp appv false
  run sh-shell myapp
  assert_status "${status}" 0
  assert_contains "${output}" "artemis() { apptainer exec"
  assert_contains "${output}" "root() { apptainer exec"
  assert_contains "${output}" "artexec() { apptainer exec"
}

test_apptainer_does_not_wrap_make_or_cmake() {
  apptainer_version_managed appv
  make_env myapp appv false
  run sh-shell myapp
  assert_status "${status}" 0
  assert_not_contains "${output}" "make() {"
  assert_not_contains "${output}" "cmake() {"
}

test_wrapper_cleanup_does_not_touch_make_or_cmake() {
  fake_native_version natv
  make_env mynat natv false
  run sh-shell mynat
  assert_status "${status}" 0
  assert_contains "${output}" "for _artenv_cmd in artemis root artexec;"
  assert_not_contains "${output}" "unset -f make"
  assert_not_contains "${output}" "unset -f cmake"
}

test_apptainer_preserves_user_defined_make_and_cmake() {
  apptainer_version_managed appv
  make_env myapp appv false
  run sh-shell myapp
  assert_status "${status}" 0
  local result
  result="$(
    make() { command make -j8 "$@"; }
    cmake() { command cmake -G Ninja "$@"; }
    eval "${output}"
    declare -f make | grep -q -- '-j8' && echo "make-preserved"
    declare -f cmake | grep -q -- 'Ninja' && echo "cmake-preserved"
    declare -f artemis >/dev/null && echo "artemis-defined"
    declare -f root >/dev/null && echo "root-defined"
  )"
  assert_contains "${result}" "make-preserved"
  assert_contains "${result}" "cmake-preserved"
  assert_contains "${result}" "artemis-defined"
  assert_contains "${result}" "root-defined"
}

test_native_preserves_user_defined_make_and_cmake() {
  fake_native_version natv
  make_env mynat natv false
  run sh-shell mynat
  assert_status "${status}" 0
  local result
  result="$(
    make() { command make -j8 "$@"; }
    cmake() { command cmake -G Ninja "$@"; }
    eval "${output}"
    declare -f make | grep -q -- '-j8' && echo "make-preserved"
    declare -f cmake | grep -q -- 'Ninja' && echo "cmake-preserved"
  )"
  assert_contains "${result}" "make-preserved"
  assert_contains "${result}" "cmake-preserved"
}

test_native_removes_apptainer_wrappers_when_evaluated() {
  apptainer_version_managed appv
  make_env myapp appv false
  fake_native_version natv
  make_env mynat natv false
  run sh-shell myapp
  local app_code="${output}"
  run sh-shell mynat
  assert_status "${status}" 0
  assert_not_contains "${output}" "() { apptainer exec"
  local result
  result="$(
    eval "${app_code}"
    eval "${output}"
    for c in artemis root artexec; do
      declare -f "${c}" >/dev/null && echo "${c}-defined"
    done
  )"
  assert_not_contains "${result}" "-defined"
}
