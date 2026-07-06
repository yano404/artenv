#!/usr/bin/env bash
# shellcheck disable=SC2154  # status/output are set by run()/run_in() in lib.sh
# Tests that `artenv shell` (via sh-shell) enables artlogin for Apptainer
# environments, mirroring the native path. These are EMIT-level tests: they
# check the shell code sh-shell prints, not the container runtime (no Apptainer
# is available here — the bind/CWD behavior must be validated on a real host).

test_apptainer_artlogin_multiuser_emits_yes_and_function() {
  apptainer_version_managed appv
  make_env mymu appv true          # use_artlogin=true, envs/mymu.artlogin.sh present
  run sh-shell mymu
  assert_status "${status}" 0
  assert_contains "${output}" "export USE_ARTLOGIN=YES"
  assert_contains "${output}" "artlogin() {"
  assert_contains "${output}" "${ARTENV_ROOT}/envs/mymu.artlogin.sh"
  assert_contains "${output}" "apptainer exec --bind"   # container wrappers still emitted
}

test_apptainer_artlogin_singleuser_emits_no_function() {
  apptainer_version_managed appv
  make_env mysu appv false
  run sh-shell mysu
  assert_status "${status}" 0
  assert_contains "${output}" "export USE_ARTLOGIN=NO"
  assert_not_contains "${output}" "artlogin() {"
}

test_apptainer_artlogin_absent_key_is_no() {
  apptainer_version_managed appv
  # env TOML without a use_artlogin key -> treated as NO (make_env always writes it)
  cat > "${ARTENV_ROOT}/envs/myabs.toml" <<EOF
[env]
version = "appv"
work = "/tmp"
EOF
  run sh-shell myabs
  assert_status "${status}" 0
  assert_contains "${output}" "export USE_ARTLOGIN=NO"
  assert_not_contains "${output}" "artlogin() {"
}

test_native_artlogin_still_emits_yes_and_function() {
  # Regression guard: the native path must keep defining artlogin so the two
  # branches don't diverge.
  fake_native_version natv
  make_env mynat natv true
  run sh-shell mynat
  assert_status "${status}" 0
  assert_contains "${output}" "export USE_ARTLOGIN=YES"
  assert_contains "${output}" "artlogin() {"
}
