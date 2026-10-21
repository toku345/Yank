#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: scripts/install-production.sh [--no-build] [--no-launch] [--allow-downgrade] [--destination <path>]
EOF
}

fail() {
  echo "error: $*" >&2
  exit 1
}

verify_existing_app() {
  local app_path="$1"
  local info_plist="${app_path}/Contents/Info.plist"
  local bundle_id

  [[ -f "${info_plist}" ]] || return 1
  bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${info_plist}" 2>/dev/null)" || \
    return 1
  [[ "${bundle_id}" == "com.toku345.Yank" ]] || return 1
  /usr/bin/codesign --verify --deep --strict "${app_path}" >/dev/null 2>&1
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/install-version.sh
source "${script_dir}/lib/install-version.sh"
repo_root="$(cd "${script_dir}/.." && pwd)"
build_root="${YANK_BUILD_ROOT:-${repo_root}/build/production}"
if [[ "${build_root}" != /* ]]; then
  build_root="${repo_root}/${build_root}"
fi
destination_app="${YANK_INSTALL_PATH:-/Applications/Yank.app}"
should_build=1
should_launch=1
allow_downgrade=0

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --no-build)
      should_build=0
      shift
      ;;
    --no-launch)
      should_launch=0
      shift
      ;;
    --allow-downgrade)
      allow_downgrade=1
      shift
      ;;
    --destination)
      [[ "$#" -ge 2 ]] || {
        usage
        exit 64
      }
      destination_app="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      exit 64
      ;;
  esac
done

if [[ "${should_build}" -eq 1 ]]; then
  "${script_dir}/build-production.sh"
fi

[[ -d "${build_root}" ]] || fail "build directory not found: ${build_root}"
build_root="$(cd "${build_root}" && pwd -P)"
source_app="${build_root}/Yank.xcarchive/Products/Applications/Yank.app"
"${script_dir}/verify-production-app.sh" "${source_app}"
source_info="${source_app}/Contents/Info.plist"
source_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${source_info}")"
source_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${source_info}")"

destination_name="$(basename "${destination_app}")"
destination_parent="$(dirname "${destination_app}")"
[[ -d "${destination_parent}" ]] || fail "destination directory not found: ${destination_parent}"
destination_parent="$(cd "${destination_parent}" && pwd -P)"
destination_app="${destination_parent}/${destination_name}"
[[ -w "${destination_parent}" ]] || \
  fail "destination is not writable: ${destination_parent}"
[[ "${destination_app}" == *.app ]] || fail "destination must end in .app"

if [[ -L "${destination_app}" ]]; then
  fail "refusing to replace a symbolic link: ${destination_app}"
fi

if [[ -e "${destination_app}" ]]; then
  existing_info="${destination_app}/Contents/Info.plist"
  verify_existing_app "${destination_app}" || \
    fail "existing destination is not a valid com.toku345.Yank app"

  if [[ "${allow_downgrade}" -eq 0 ]]; then
    existing_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${existing_info}")"
    existing_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${existing_info}")"
    check_install_version "${existing_version}" "${existing_build}" \
      "${source_version}" "${source_build}" || exit 1
  fi
fi

if /usr/bin/pgrep -x Yank >/dev/null 2>&1; then
  fail "a process named Yank is running; quit it before installing"
fi

stage_root="$(mktemp -d "${destination_parent}/.Yank.install.XXXXXX")"
staged_app="${stage_root}/Yank.app"
backup_app="${stage_root}/Yank.previous.app"
had_existing=0
new_install_attempted=0
install_committed=0

cleanup() {
  status="$?"
  trap - EXIT HUP INT TERM
  cleanup_stage=1
  if [[ "${status}" -ne 0 && "${install_committed}" -eq 0 ]]; then
    if [[ "${new_install_attempted}" -eq 1 && -e "${destination_app}" ]]; then
      if ! /bin/mv "${destination_app}" "${stage_root}/Yank.failed.app"; then
        echo "error: failed to move the unverified app out of ${destination_app}" >&2
        cleanup_stage=0
      fi
    fi
    if [[ "${had_existing}" -eq 1 ]]; then
      if [[ -e "${backup_app}" && ! -e "${destination_app}" ]]; then
        if ! /bin/mv "${backup_app}" "${destination_app}"; then
          echo "error: failed to restore previous app from ${backup_app}" >&2
          cleanup_stage=0
        elif ! verify_existing_app "${destination_app}"; then
          echo "error: restored app at ${destination_app} failed verification" >&2
          cleanup_stage=0
        fi
      elif [[ ! -e "${backup_app}" && "${new_install_attempted}" -eq 0 && -e "${destination_app}" ]]; then
        : # The move to the backup did not complete; the original is still in place.
      else
        echo "error: previous app could not be restored automatically" >&2
        cleanup_stage=0
      fi
    fi
  fi
  if [[ "${cleanup_stage}" -eq 1 ]]; then
    /bin/rm -rf "${stage_root}"
  else
    echo "error: recovery files were preserved at ${stage_root}" >&2
  fi
  exit "${status}"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

/usr/bin/ditto "${source_app}" "${staged_app}"
"${script_dir}/verify-production-app.sh" "${staged_app}"

if [[ -e "${destination_app}" ]]; then
  had_existing=1
  /bin/mv "${destination_app}" "${backup_app}"
fi

new_install_attempted=1
/bin/mv "${staged_app}" "${destination_app}" || fail "failed to install ${destination_app}"
"${script_dir}/verify-production-app.sh" "${destination_app}"
install_committed=1

echo "Installed: ${destination_app}"

if [[ "${should_launch}" -eq 1 ]]; then
  /usr/bin/open "${destination_app}"
  echo "Launched: ${destination_app}"
fi
