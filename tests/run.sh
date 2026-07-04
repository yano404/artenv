#!/usr/bin/env bash
# artenv test runner (plain bash, no external framework).
#
#   ./tests/run.sh            # run all tests
#
# Each test_* function runs in its own subshell against a fresh, isolated
# ARTENV_ROOT sandbox. The real ~/.artenv is never used.

set -uo pipefail

ARTENV_REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
export ARTENV_REPO

command -v yq >/dev/null 2>&1 || { echo "yq is required to run the tests (dnf install yq)" >&2; exit 2; }

# shellcheck source=/dev/null
source "${ARTENV_REPO}/tests/lib.sh"

for tf in "${ARTENV_REPO}"/tests/test_*.sh; do
  # shellcheck source=/dev/null
  source "${tf}"
done

mapfile -t TESTS < <(declare -F | awk '{print $3}' | grep '^test_' | sort)

pass=0 fail=0
declare -a failed=()

for t in "${TESTS[@]}"; do
  if out="$(
        set -e
        setup_sandbox
        trap teardown_sandbox EXIT
        "${t}"
      )" 2>&1; then
    printf 'ok   - %s\n' "${t}"
    pass=$((pass + 1))
  else
    printf 'FAIL - %s\n' "${t}"
    [[ -n "${out}" ]] && printf '%s\n' "${out}" | sed 's/^/       /'
    fail=$((fail + 1))
    failed+=("${t}")
  fi
done

echo "----------------------------------------"
printf '%d passed, %d failed (%d total)\n' "${pass}" "${fail}" "${#TESTS[@]}"

if [[ "${fail}" -gt 0 ]]; then
  printf 'failed: %s\n' "${failed[*]}"
  exit 1
fi
