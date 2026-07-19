#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: $0 <Yank.app>" >&2
}

fail() {
  echo "error: $*" >&2
  exit 1
}

[[ "$#" -eq 1 ]] || {
  usage
  exit 64
}

app_path="$1"
info_plist="${app_path}/Contents/Info.plist"
executable="${app_path}/Contents/MacOS/Yank"

[[ -d "${app_path}" ]] || fail "app bundle not found: ${app_path}"
[[ -f "${info_plist}" ]] || fail "Info.plist not found: ${info_plist}"
[[ -x "${executable}" ]] || fail "executable not found: ${executable}"

bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${info_plist}")"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${info_plist}")"
build_number="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${info_plist}")"

[[ "${bundle_id}" == "com.toku345.Yank" ]] || \
  fail "unexpected bundle identifier: ${bundle_id}"
[[ "${version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || \
  fail "CFBundleShortVersionString is not semantic: ${version}"
[[ "${build_number}" =~ ^[1-9][0-9]*$ ]] || \
  fail "CFBundleVersion is not a positive integer: ${build_number}"

if [[ -n "${YANK_EXPECTED_VERSION:-}" && "${version}" != "${YANK_EXPECTED_VERSION}" ]]; then
  fail "expected version ${YANK_EXPECTED_VERSION}, found ${version}"
fi
if [[ -n "${YANK_EXPECTED_BUILD:-}" && "${build_number}" != "${YANK_EXPECTED_BUILD}" ]]; then
  fail "expected build ${YANK_EXPECTED_BUILD}, found ${build_number}"
fi

/usr/bin/codesign --verify --deep --strict --verbose=2 "${app_path}"

signature_info="$(/usr/bin/codesign -dv --verbose=4 "${app_path}" 2>&1)"
if grep -Fq 'Signature=adhoc' <<<"${signature_info}"; then
  fail "ad-hoc signatures are not accepted for a production app"
fi
if ! grep -Eq '^TeamIdentifier=[A-Z0-9]+$' <<<"${signature_info}"; then
  fail "the production app has no signing team"
fi
if ! grep -Eq 'flags=.*runtime' <<<"${signature_info}"; then
  fail "hardened runtime is not enabled"
fi

entitlements_path="$(mktemp -t yank-entitlements.XXXXXX)"
trap '/bin/rm -f "${entitlements_path}"' EXIT
/usr/bin/codesign -d --entitlements - --xml "${app_path}" >"${entitlements_path}" 2>/dev/null
/usr/bin/plutil -lint "${entitlements_path}" >/dev/null

if get_task_allow="$(/usr/libexec/PlistBuddy \
  -c 'Print :com.apple.security.get-task-allow' "${entitlements_path}" 2>/dev/null)" && \
  [[ "${get_task_allow}" == "true" ]]; then
  fail "com.apple.security.get-task-allow must not be enabled"
fi

if app_sandbox="$(/usr/libexec/PlistBuddy \
  -c 'Print :com.apple.security.app-sandbox' "${entitlements_path}" 2>/dev/null)" && \
  [[ "${app_sandbox}" == "true" ]]; then
  fail "com.apple.security.app-sandbox must not be enabled"
fi

architectures="$(/usr/bin/lipo -archs "${executable}")"
for required_architecture in arm64 x86_64; do
  if [[ " ${architectures} " != *" ${required_architecture} "* ]]; then
    fail "missing ${required_architecture} architecture: ${architectures}"
  fi
done

echo "Verified Yank ${version} (${build_number})"
echo "Bundle identifier: ${bundle_id}"
echo "Architectures: ${architectures}"
