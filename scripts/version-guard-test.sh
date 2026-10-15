#!/usr/bin/env bash
# Table-driven tests for the version guard in scripts/version-guard.sh.
#
# Sources the pure helper only. It never sources install-production.sh, so it
# cannot build, install, launch, or touch an application bundle, the real
# clipboard, or the developer's store. Safe to run in CI and locally.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=version-guard.sh
source "${script_dir}/version-guard.sh"

checks=0
failures=0

expect() {
  local actual="$1"
  local expected="$2"
  local context="$3"

  checks=$((checks + 1))
  if [[ "${actual}" != "${expected}" ]]; then
    echo "FAIL: ${context}: expected '${expected}', got '${actual}'" >&2
    failures=$((failures + 1))
  fi
}

# semver_compare: left|right|expected
while IFS='|' read -r left right expected; do
  [[ -n "${left}" ]] || continue
  expect "$(semver_compare "${left}" "${right}")" "${expected}" \
    "semver_compare ${left} ${right}"
done <<'TABLE'
0.9.0|0.10.0|-1
0.10.0|0.9.0|1
1.0.0|1.0.0|0
1.2.3|2.0.0|-1
2.0.0|1.2.3|1
1.0.9|1.0.10|-1
1.0.10|1.0.9|1
10.0.0|9.9.9|1
0.0.1|0.0.2|-1
1.08.0|1.9.0|-1
1.9.0|1.08.0|1
TABLE

# install_version_decision: existing_version|existing_build|source_version|source_build|expected
while IFS='|' read -r existing_version existing_build source_version source_build expected; do
  [[ -n "${existing_version}" ]] || continue
  expect \
    "$(install_version_decision \
      "${existing_version}" "${existing_build}" "${source_version}" "${source_build}")" \
    "${expected}" \
    "decision ${existing_version}(${existing_build}) -> ${source_version}(${source_build})"
done <<'TABLE'
0.9.0|1|0.10.0|1|ok
1.0.0|1|1.0.0|1|ok
1.0.0|1|1.0.0|2|ok
1.0.0|2|1.0.0|1|downgrade
1.0.0|08|1.0.0|9|ok
1.0.0|010|1.0.0|9|downgrade
2.0.0|5|1.0.0|99|downgrade
1.2.3|1|2.0.0|1|ok
1.0.0|99|1.0.1|1|ok
0.10.0|1|0.9.0|1|downgrade
1.0|1|1.0.0|1|invalid-existing-version
1.0.0.0|1|1.0.0|1|invalid-existing-version
1.0.0|1|1.0|1|invalid-source-version
1.0.0|1|v1.0.0|1|invalid-source-version
1.0.0|x|1.0.0|1|invalid-build-number
1.0.0|1|1.0.0|x|invalid-build-number
1.0.0||1.0.0|1|invalid-build-number
TABLE

if [[ "${failures}" -ne 0 ]]; then
  echo "FAILED: ${failures} of ${checks} checks failed" >&2
  exit 1
fi

echo "version-guard: ${checks} checks passed"
