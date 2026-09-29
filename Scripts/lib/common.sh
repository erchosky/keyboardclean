#!/bin/bash

require_command() {
  local command_name="$1"
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "ERROR: no se encontro el comando requerido: $command_name" >&2
    return 1
  fi
}

make_temp_dir() {
  local prefix="$1"
  local temp_root="${TMPDIR:-/tmp}"
  mktemp -d "${temp_root%/}/${prefix}.XXXXXX"
}

cleanup_temp_dir() {
  local directory="${1:-}"
  local temp_root="${TMPDIR:-/tmp}"
  temp_root="${temp_root%/}"
  [[ -n "$directory" && -d "$directory" ]] || return 0

  case "$directory" in
    "$temp_root"/*) rm -rf -- "$directory" ;;
    *)
      echo "ERROR: se rechazo limpiar una ruta temporal inesperada: $directory" >&2
      return 1
      ;;
  esac
}

clean_app_metadata() {
  local app_path="$1"
  xattr -cr "$app_path" 2>/dev/null || true
  xattr -d com.apple.FinderInfo "$app_path" 2>/dev/null || true
  xattr -dr com.apple.FinderInfo "$app_path" 2>/dev/null || true
  xattr -cr "$app_path" 2>/dev/null || true
}

verify_app_signature() {
  local app_path="$1"
  local attempt

  for attempt in 1 2 3; do
    clean_app_metadata "$app_path"
    if codesign --verify --strict --verbose=2 "$app_path" >/dev/null 2>&1; then
      codesign --verify --strict --verbose=2 "$app_path"
      return 0
    fi
    sleep 0.2
  done

  clean_app_metadata "$app_path"
  codesign --verify --strict --verbose=2 "$app_path"
}

verify_release_entitlements() {
  local app_path="$1"
  local get_task_allow

  get_task_allow="$(
    codesign -d --entitlements :- "$app_path" 2>/dev/null \
      | plutil -extract com.apple.security.get-task-allow raw -o - - 2>/dev/null \
      || true
  )"

  if [[ "$get_task_allow" == "true" || "$get_task_allow" == "1" ]]; then
    echo "ERROR: el artefacto Release contiene com.apple.security.get-task-allow" >&2
    return 1
  fi
}
