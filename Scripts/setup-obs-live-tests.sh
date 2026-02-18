#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"

OBS_CONFIG_ROOT="${HOME}/Library/Application Support/obs-studio"
OBS_WS_CONFIG="${OBS_CONFIG_ROOT}/plugin_config/obs-websocket/config.json"
OBS_PROFILES_ROOT="${OBS_CONFIG_ROOT}/basic/profiles"

SENTINEL_ROOT="${HOME}/.controllerkeys"
LIVE_SENTINEL="${SENTINEL_ROOT}/obs_live_tests_enabled"
MUTATION_SENTINEL="${SENTINEL_ROOT}/obs_live_tests_allow_output_mutations"

BACKUP_ROOT="${SENTINEL_ROOT}/obs-live-test-backups"
LAST_BACKUP_POINTER="${BACKUP_ROOT}/.last_backup"

OBS_WS_PORT="${OBS_WS_PORT:-4455}"
OBS_WS_PASSWORD="${OBS_WS_PASSWORD:-controllerkeys-live-tests}"

usage() {
  cat <<EOF
Usage:
  ${SCRIPT_NAME} apply
  ${SCRIPT_NAME} restore [backup_dir]
  ${SCRIPT_NAME} status

Commands:
  apply   Backup current OBS test-related config, then apply live-test settings.
  restore Restore files from latest backup (or explicit backup_dir).
  status  Show current OBS live-test readiness.

Environment:
  OBS_WS_PORT       Websocket port to write (default: 4455)
  OBS_WS_PASSWORD   Websocket password to write (default: controllerkeys-live-tests)
EOF
}

log() {
  printf '[obs-live-tests] %s\n' "$*"
}

fail() {
  printf '[obs-live-tests] ERROR: %s\n' "$*" >&2
  exit 1
}

require_numeric_port() {
  if ! [[ "${OBS_WS_PORT}" =~ ^[0-9]+$ ]]; then
    fail "OBS_WS_PORT must be numeric, got: ${OBS_WS_PORT}"
  fi
}

backup_path_for() {
  local original="$1"
  local rel="${original#/}"
  printf '%s/files/%s' "${BACKUP_DIR}" "${rel}"
}

backup_file() {
  local path="$1"
  local backup_target
  backup_target="$(backup_path_for "${path}")"
  if [[ -e "${path}" ]]; then
    mkdir -p "$(dirname "${backup_target}")"
    cp -p "${path}" "${backup_target}"
    printf '%s\n' "${path}" >> "${BACKUP_DIR}/meta/existed_paths.txt"
  else
    printf '%s\n' "${path}" >> "${BACKUP_DIR}/meta/missing_paths.txt"
  fi
}

upsert_ini_key() {
  local file="$1"
  local section="$2"
  local key="$3"
  local value="$4"
  local tmp
  tmp="$(mktemp)"

  awk \
    -v section="${section}" \
    -v key="${key}" \
    -v value="${value}" \
    '
      BEGIN {
        in_section = 0
        section_seen = 0
        key_seen = 0
      }
      /^\[.*\]$/ {
        if (in_section && !key_seen) {
          print key "=" value
        }
        in_section = ($0 == "[" section "]")
        if (in_section) {
          section_seen = 1
          key_seen = 0
        }
        print
        next
      }
      {
        if (in_section && $0 ~ ("^" key "=")) {
          if (!key_seen) {
            print key "=" value
            key_seen = 1
          }
          next
        }
        print
      }
      END {
        if (section_seen) {
          if (in_section && !key_seen) {
            print key "=" value
          }
        } else {
          print ""
          print "[" section "]"
          print key "=" value
        }
      }
    ' "${file}" > "${tmp}"

  mv "${tmp}" "${file}"
}

apply_obs_ws_config() {
  require_numeric_port
  mkdir -p "$(dirname "${OBS_WS_CONFIG}")"

  local tmp
  tmp="$(mktemp)"

  if [[ -f "${OBS_WS_CONFIG}" ]] && jq empty "${OBS_WS_CONFIG}" >/dev/null 2>&1; then
    jq \
      --arg password "${OBS_WS_PASSWORD}" \
      --argjson port "${OBS_WS_PORT}" \
      '
        .alerts_enabled = false
        | .auth_required = true
        | .first_load = false
        | .server_enabled = true
        | .server_password = $password
        | .server_port = $port
      ' \
      "${OBS_WS_CONFIG}" > "${tmp}"
  else
    cat > "${tmp}" <<EOF
{
  "alerts_enabled": false,
  "auth_required": true,
  "first_load": false,
  "server_enabled": true,
  "server_password": "${OBS_WS_PASSWORD}",
  "server_port": ${OBS_WS_PORT}
}
EOF
  fi

  mv "${tmp}" "${OBS_WS_CONFIG}"
  chmod 600 "${OBS_WS_CONFIG}" || true
}

apply_profile_tweaks() {
  if [[ ! -d "${OBS_PROFILES_ROOT}" ]]; then
    log "OBS profiles directory not found: ${OBS_PROFILES_ROOT} (skipping profile tweaks)"
    return
  fi

  local profile_files
  mapfile -t profile_files < <(find "${OBS_PROFILES_ROOT}" -type f -name basic.ini | sort)

  if [[ "${#profile_files[@]}" -eq 0 ]]; then
    log "No OBS profile basic.ini files found (skipping profile tweaks)"
    return
  fi

  for ini in "${profile_files[@]}"; do
    upsert_ini_key "${ini}" "Output" "Mode" "Advanced"
    upsert_ini_key "${ini}" "SimpleOutput" "RecRB" "true"
    upsert_ini_key "${ini}" "SimpleOutput" "RecRBTime" "20"
    upsert_ini_key "${ini}" "SimpleOutput" "RecRBSize" "512"
    upsert_ini_key "${ini}" "AdvOut" "RecType" "Standard"
    upsert_ini_key "${ini}" "AdvOut" "RecRB" "true"
    upsert_ini_key "${ini}" "AdvOut" "RecRBTime" "20"
    upsert_ini_key "${ini}" "AdvOut" "RecRBSize" "512"
    upsert_ini_key "${ini}" "AdvOut" "RecSplitFileType" "Time"
    upsert_ini_key "${ini}" "AdvOut" "RecSplitFileTime" "15"
    upsert_ini_key "${ini}" "AdvOut" "RecSplitFileSize" "2048"
  done

  log "Updated replay-buffer and split-record settings in ${#profile_files[@]} profile(s)"
}

apply_sentinels() {
  mkdir -p "${SENTINEL_ROOT}"
  : > "${LIVE_SENTINEL}"
  : > "${MUTATION_SENTINEL}"
}

create_backup() {
  mkdir -p "${BACKUP_ROOT}"
  BACKUP_DIR="${BACKUP_ROOT}/$(date +%Y%m%d-%H%M%S)"
  mkdir -p "${BACKUP_DIR}/meta"

  : > "${BACKUP_DIR}/meta/existed_paths.txt"
  : > "${BACKUP_DIR}/meta/missing_paths.txt"

  backup_file "${OBS_WS_CONFIG}"
  backup_file "${LIVE_SENTINEL}"
  backup_file "${MUTATION_SENTINEL}"

  if [[ -d "${OBS_PROFILES_ROOT}" ]]; then
    while IFS= read -r ini; do
      backup_file "${ini}"
    done < <(find "${OBS_PROFILES_ROOT}" -type f -name basic.ini | sort)
  fi

  printf '%s\n' "${BACKUP_DIR}" > "${LAST_BACKUP_POINTER}"
}

run_apply() {
  command -v jq >/dev/null 2>&1 || fail "jq is required. Install with: brew install jq"

  create_backup

  apply_obs_ws_config
  apply_profile_tweaks
  apply_sentinels

  log "Applied OBS live-test settings"
  log "Backup saved to: ${BACKUP_DIR}"
  log "Wrote websocket config: ${OBS_WS_CONFIG} (port ${OBS_WS_PORT})"
  log "Enabled sentinels: ${LIVE_SENTINEL}, ${MUTATION_SENTINEL}"
  log "Restart OBS before running live tests."
}

restore_path() {
  local path="$1"
  local rel="${path#/}"
  local src="${RESTORE_DIR}/files/${rel}"
  mkdir -p "$(dirname "${path}")"
  cp -p "${src}" "${path}"
}

run_restore() {
  local requested="${1:-}"

  if [[ -n "${requested}" ]]; then
    RESTORE_DIR="${requested}"
  elif [[ -f "${LAST_BACKUP_POINTER}" ]]; then
    RESTORE_DIR="$(cat "${LAST_BACKUP_POINTER}")"
  else
    fail "No backup pointer found. Provide a backup dir explicitly."
  fi

  [[ -d "${RESTORE_DIR}" ]] || fail "Backup directory not found: ${RESTORE_DIR}"
  [[ -f "${RESTORE_DIR}/meta/existed_paths.txt" ]] || fail "Invalid backup metadata in ${RESTORE_DIR}"
  [[ -f "${RESTORE_DIR}/meta/missing_paths.txt" ]] || fail "Invalid backup metadata in ${RESTORE_DIR}"

  while IFS= read -r path; do
    [[ -n "${path}" ]] || continue
    restore_path "${path}"
  done < "${RESTORE_DIR}/meta/existed_paths.txt"

  while IFS= read -r path; do
    [[ -n "${path}" ]] || continue
    if [[ -e "${path}" ]]; then
      rm -f "${path}"
    fi
  done < "${RESTORE_DIR}/meta/missing_paths.txt"

  log "Restored OBS live-test settings from: ${RESTORE_DIR}"
  log "Restart OBS to reload restored config."
}

run_status() {
  log "OBS websocket config: ${OBS_WS_CONFIG}"
  if [[ -f "${OBS_WS_CONFIG}" ]] && jq empty "${OBS_WS_CONFIG}" >/dev/null 2>&1; then
    jq '{server_enabled, auth_required, server_port, server_password_set: ((.server_password // "") != "")}' "${OBS_WS_CONFIG}"
  else
    log "websocket config missing or invalid JSON"
  fi

  if [[ -f "${LIVE_SENTINEL}" ]]; then
    log "sentinel present: ${LIVE_SENTINEL}"
  else
    log "sentinel missing: ${LIVE_SENTINEL}"
  fi

  if [[ -f "${MUTATION_SENTINEL}" ]]; then
    log "sentinel present: ${MUTATION_SENTINEL}"
  else
    log "sentinel missing: ${MUTATION_SENTINEL}"
  fi

  if [[ -f "${LAST_BACKUP_POINTER}" ]]; then
    log "last backup: $(cat "${LAST_BACKUP_POINTER}")"
  else
    log "last backup: none"
  fi

  if [[ -d "${OBS_PROFILES_ROOT}" ]]; then
    local count
    count="$(find "${OBS_PROFILES_ROOT}" -type f -name basic.ini | wc -l | tr -d ' ')"
    log "profile basic.ini files: ${count}"
  fi
}

main() {
  local cmd="${1:-status}"
  case "${cmd}" in
    apply)
      run_apply
      ;;
    restore)
      run_restore "${2:-}"
      ;;
    status)
      run_status
      ;;
    -h|--help|help)
      usage
      ;;
    *)
      usage
      fail "Unknown command: ${cmd}"
      ;;
  esac
}

main "$@"
