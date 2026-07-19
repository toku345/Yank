#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "error: $*" >&2
  exit 1
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
build_root="${YANK_BUILD_ROOT:-${repo_root}/build/production}"
if [[ "${build_root}" != /* ]]; then
  build_root="${repo_root}/${build_root}"
fi

for command_name in xcodebuild xcodegen swiftlint; do
  command -v "${command_name}" >/dev/null 2>&1 || \
    fail "${command_name} is not installed or not on PATH"
done

[[ -f "${repo_root}/SupportingFiles/Local.xcconfig" ]] || \
  fail "SupportingFiles/Local.xcconfig is required; see docs/dev-signing.md"

mkdir -p "${build_root}"
build_root="$(cd "${build_root}" && pwd -P)"
archive_path="${build_root}/Yank.xcarchive"
app_path="${archive_path}/Products/Applications/Yank.app"
[[ "${archive_path}" != "/Yank.xcarchive" ]] || fail "unsafe archive path"
if [[ -e "${archive_path}" ]]; then
  /bin/rm -rf "${archive_path}"
fi

cd "${repo_root}"
swiftlint lint --strict
xcodegen generate
xcodebuild \
  -project Yank.xcodeproj \
  -scheme Yank-Production \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "${archive_path}" \
  -xcconfig "${repo_root}/SupportingFiles/Base.xcconfig" \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  ENABLE_CODE_COVERAGE=NO \
  archive

"${script_dir}/verify-production-app.sh" "${app_path}"

echo "Archive: ${archive_path}"
echo "Application: ${app_path}"
