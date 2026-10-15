#!/usr/bin/env bash
# Sourceable version policy only: no installation, filesystem access, or shell options.
# semver_compare expects validated MAJOR.MINOR.PATCH inputs.

semver_compare() {
  local left="$1"
  local right="$2"
  local -a left_parts=()
  local -a right_parts=()
  local index left_number right_number

  IFS=. read -r -a left_parts <<< "${left}"
  IFS=. read -r -a right_parts <<< "${right}"
  for index in 0 1 2; do
    left_number=$((10#${left_parts[${index}]}))
    right_number=$((10#${right_parts[${index}]}))
    if ((left_number > right_number)); then
      echo 1
      return
    fi
    if ((left_number < right_number)); then
      echo -1
      return
    fi
  done
  echo 0
}

check_install_version() {
  local existing_version="$1"
  local existing_build="$2"
  local source_version="$3"
  local source_build="$4"
  local version_order

  [[ "${existing_version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
    echo "error: existing app has a non-semantic version; use --allow-downgrade to replace it" >&2
    return 1
  }
  [[ "${source_version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
    echo "error: source app has a non-semantic version" >&2
    return 1
  }
  [[ "${existing_build}" =~ ^[0-9]+$ && "${source_build}" =~ ^[0-9]+$ ]] || {
    echo "error: app build numbers must be integers" >&2
    return 1
  }

  version_order="$(semver_compare "${existing_version}" "${source_version}")"
  if [[ "${version_order}" -gt 0 ]] || \
    { [[ "${version_order}" -eq 0 ]] && ((10#${existing_build} > 10#${source_build})); }; then
    echo "error: refusing to downgrade ${existing_version} (${existing_build}) to ${source_version} (${source_build}); use --allow-downgrade to override" >&2
    return 1
  fi
  return 0
}
