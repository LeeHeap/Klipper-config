#!/usr/bin/env bash

#####################################################################
### GitHub config backup for Voron printer
#####################################################################

config_folder=~/printer_data/config
klipper_folder=~/klipper
moonraker_folder=~/moonraker
fluidd_folder=~/fluidd

#####################################################################

set -e  # Exit on any error

grab_version() {
  local versions=""

  if [[ -d "${klipper_folder}" ]]; then
    cd "${klipper_folder}"
    versions+="Klipper: $(git describe --always --tags 2>/dev/null || git rev-parse --short=7 HEAD)"
  fi

  if [[ -d "${moonraker_folder}" ]]; then
    cd "${moonraker_folder}"
    versions+=" | Moonraker: $(git describe --always --tags 2>/dev/null || git rev-parse --short=7 HEAD)"
  fi

  if [[ -f "${fluidd_folder}/.version" ]]; then
    versions+=" | Fluidd: $(head -n 1 "${fluidd_folder}/.version")"
  fi

  echo "${versions}"
}

push_config() {
  cd "${config_folder}" || { echo "ERROR: Config folder not found"; exit 1; }

  # Only pull if remote has changes (avoids unnecessary merge commits)
  git fetch origin 2>/dev/null
  local LOCAL=$(git rev-parse HEAD)
  local REMOTE=$(git rev-parse @{u} 2>/dev/null || echo "${LOCAL}")
  if [[ "${LOCAL}" != "${REMOTE}" ]]; then
    git pull --rebase --autostash || { echo "ERROR: git pull failed"; exit 1; }
  fi

  # Check if there are actually changes to commit
  if git diff --quiet && git diff --staged --quiet; then
    echo "No config changes to backup"
    exit 0
  fi

  git add -A
  local version_info
  version_info=$(grab_version)
  git commit -m "Autocommit $(date +'%Y-%m-%d %H:%M')" -m "${version_info}"
  git push || echo "WARNING: git push failed — will retry next run"
}

push_config