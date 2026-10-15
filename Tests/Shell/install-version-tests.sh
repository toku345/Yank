#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# Only source the pure helper. Never source or execute the installer here.
# shellcheck source=scripts/lib/install-version.sh
source "${repo_root}/scripts/lib/install-version.sh"

cases=0
while IFS='|' read -r left right expected; do
  actual="$(semver_compare "${left}" "${right}")"
  if [[ "${actual}" != "${expected}" ]]; then
    echo "FAIL: compare ${left} vs ${right}: expected ${expected}, got ${actual}" >&2
    exit 1
  fi
  cases=$((cases + 1))
done <<'CASES'
0.9.0|0.10.0|-1
0.10.0|0.9.0|1
1.0.0|1.0.0|0
1.2.3|2.0.0|-1
2.0.0|1.2.3|1
1.2.9|1.2.10|-1
1.2.10|1.2.9|1
1.9.99|1.10.0|-1
1.10.0|1.9.99|1
9.99.99|10.0.0|-1
10.0.0|9.99.99|1
0.0.0|0.0.0|0
01.008.009|1.8.9|0
1.08.09|1.8.10|-1
1.08.010|1.8.9|1
CASES

# Columns: existing version/build, source version/build, status, diagnostic.
# A successful check must be silent; rejection must include the expected reason.
while IFS='|' read -r existing_version existing_build source_version source_build expected_status expected_message; do
  status=0
  output="$(check_install_version "${existing_version}" "${existing_build}" \
    "${source_version}" "${source_build}" 2>&1)" || status=$?
  if [[ "${status}" != "${expected_status}" || "${output}" != "${expected_message}" ]]; then
    echo "FAIL: ${existing_version} (${existing_build}) -> ${source_version} (${source_build})" >&2
    echo "expected status ${expected_status}: ${expected_message}" >&2
    echo "actual status ${status}: ${output}" >&2
    exit 1
  fi
  cases=$((cases + 1))
done <<'CASES'
0.9.0|99|0.10.0|1|0|
0.10.0|1|0.9.0|99|1|error: refusing to downgrade 0.10.0 (1) to 0.9.0 (99); use --allow-downgrade to override
1.2.3|99|2.0.0|1|0|
2.0.0|1|1.2.3|99|1|error: refusing to downgrade 2.0.0 (1) to 1.2.3 (99); use --allow-downgrade to override
1.0.0|9|1.0.0|10|0|
1.0.0|10|1.0.0|9|1|error: refusing to downgrade 1.0.0 (10) to 1.0.0 (9); use --allow-downgrade to override
1.0.0|10|1.0.0|10|0|
1.0.0|09|1.0.0|010|0|
1.0.0|010|1.0.0|09|1|error: refusing to downgrade 1.0.0 (010) to 1.0.0 (09); use --allow-downgrade to override
01.008.009|010|1.8.9|10|0|
01.008.009|010|1.8.9|09|1|error: refusing to downgrade 01.008.009 (010) to 1.8.9 (09); use --allow-downgrade to override
1.0.0|0|1.0.0|1|0|
|1|1.0.0|1|1|error: existing app has a non-semantic version; use --allow-downgrade to replace it
1.0|1|1.0.0|1|1|error: existing app has a non-semantic version; use --allow-downgrade to replace it
1.0.0.0|1|1.0.0|1|1|error: existing app has a non-semantic version; use --allow-downgrade to replace it
v1.0.0|1|1.0.0|1|1|error: existing app has a non-semantic version; use --allow-downgrade to replace it
1.0.0-beta|1|1.0.0|1|1|error: existing app has a non-semantic version; use --allow-downgrade to replace it
1.0.0|1||1|1|error: source app has a non-semantic version
1.0.0|1|1.0|1|1|error: source app has a non-semantic version
1.0.0|1|1.0.0.0|1|1|error: source app has a non-semantic version
1.0.0|1|v1.0.0|1|1|error: source app has a non-semantic version
1.0.0|1|1.0.0-beta|1|1|error: source app has a non-semantic version
1.0.0|1| 1.0.0|1|1|error: source app has a non-semantic version
1.0.0||1.0.0|1|1|error: app build numbers must be integers
1.0.0|1|1.0.0||1|error: app build numbers must be integers
1.0.0|-1|1.0.0|1|1|error: app build numbers must be integers
1.0.0|1|1.0.0|-1|1|error: app build numbers must be integers
1.0.0|1.5|1.0.0|1|1|error: app build numbers must be integers
1.0.0|1|1.0.0|1.5|1|error: app build numbers must be integers
1.0.0|a|1.0.0|1|1|error: app build numbers must be integers
1.0.0|1|1.0.0|1a|1|error: app build numbers must be integers
1.0.0|1|1.0.0| 1|1|error: app build numbers must be integers
CASES

echo "PASS: ${cases} installer version-policy cases"
