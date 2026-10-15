#!/usr/bin/env bash
# Pure, side-effect-free helpers shared by install-production.sh and its tests.
#
# This file is meant to be sourced, not executed. Sourcing it only defines
# functions; it never reads arguments, touches the filesystem, builds, or
# installs anything, so it is safe to source from a test.

# Compares two semantic versions that each have three numeric components.
#
# Prints 1 when left > right, -1 when left < right, and 0 when equal. The 10#
# prefix forces base-10 parsing so a component with a leading zero (for example
# 08) is not misread as octal.
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

# Classifies whether a source app may replace an installed app without
# --allow-downgrade. Prints exactly one decision token:
#   ok                       - the install is not a downgrade
#   invalid-existing-version - the installed version is not X.Y.Z
#   invalid-source-version   - the source version is not X.Y.Z
#   invalid-build-number     - a build number is not a non-negative integer
#   downgrade                - the source is older; --allow-downgrade is needed
install_version_decision() {
  local existing_version="$1"
  local existing_build="$2"
  local source_version="$3"
  local source_build="$4"
  local version_order

  [[ "${existing_version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
    echo invalid-existing-version
    return
  }
  [[ "${source_version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
    echo invalid-source-version
    return
  }
  [[ "${existing_build}" =~ ^[0-9]+$ && "${source_build}" =~ ^[0-9]+$ ]] || {
    echo invalid-build-number
    return
  }

  version_order="$(semver_compare "${existing_version}" "${source_version}")"
  if [[ "${version_order}" -gt 0 ]] || \
    { [[ "${version_order}" -eq 0 ]] && ((10#${existing_build} > 10#${source_build})); }; then
    echo downgrade
    return
  fi
  echo ok
}
