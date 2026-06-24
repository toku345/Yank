#!/usr/bin/env bash
set -euo pipefail

missing=0
for command_name in xcodebuild xcodegen swiftlint; do
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "error: ${command_name} is not installed or not on PATH" >&2
    missing=1
  fi
done

if [[ "${missing}" -ne 0 ]]; then
  exit 127
fi

swiftlint lint --strict
xcodegen generate
xcodebuild \
  -project Yank.xcodeproj \
  -scheme Yank \
  -configuration Debug \
  -destination 'platform=macOS' \
  test
