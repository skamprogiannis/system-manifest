#!/usr/bin/env bash
# shellcheck disable=SC2034

read_expected_config_revision() {
  local error_log=""
  local result=""

  error_log=$(mktemp)
  if ! result=$(nix eval --raw "$FLAKE_DIR#nixosConfigurations.usb.config.system.configurationRevision" 2>"$error_log"); then
    echo "Warning: failed to evaluate USB configurationRevision from $FLAKE_DIR" >&2
    if [ -s "$error_log" ]; then
      cat "$error_log" >&2
    fi
    rm -f "$error_log"
    return 1
  fi

  rm -f "$error_log"
  printf '%s' "$result"
}

read_desired_system_toplevel() {
  local error_log=""
  local result=""

  error_log=$(mktemp)
  if ! result=$(nix eval --raw "$FLAKE_DIR#nixosConfigurations.usb.config.system.build.toplevel" 2>"$error_log"); then
    echo "Warning: failed to evaluate desired USB system toplevel from $FLAKE_DIR" >&2
    if [ -s "$error_log" ]; then
      cat "$error_log" >&2
    fi
    rm -f "$error_log"
    return 1
  fi

  rm -f "$error_log"
  printf '%s' "$result"
}

capture_desired_system_metadata() {
  DESIRED_SYSTEM_TOPLEVEL=""
  DESIRED_INIT_RELATIVE=""

  if ! DESIRED_SYSTEM_TOPLEVEL="$(read_desired_system_toplevel)"; then
    return 1
  fi

  DESIRED_INIT_RELATIVE="${DESIRED_SYSTEM_TOPLEVEL#/nix/store/}/init"
}

version_json_field() {
  local key="$1"
  local value=""
  local jq_bin="${UPDATE_USB_JQ:-jq}"

  if ! value=$("$jq_bin" -r --arg key "$key" '.[$key] // empty' 2>/dev/null); then
    echo "Warning: failed to parse nixos-version JSON for key '$key'" >&2
    return 1
  fi

  printf '%s\n' "$value"
}

capture_target_system_metadata() {
  local version_json=""
  local version_error_log=""

  TARGET_SYSTEM_TOPLEVEL="$(readlink -f "$MOUNT_POINT/nix/var/nix/profiles/system" 2>/dev/null || true)"
  TARGET_INIT_RELATIVE=""
  if [ -n "$TARGET_SYSTEM_TOPLEVEL" ]; then
    TARGET_INIT_RELATIVE="${TARGET_SYSTEM_TOPLEVEL#/nix/store/}/init"
  fi

  version_error_log=$(mktemp)
  if ! version_json="$(chroot "$MOUNT_POINT" /nix/var/nix/profiles/system/sw/bin/nixos-version --json 2>"$version_error_log")"; then
    echo "Warning: failed to read installed USB system metadata via nixos-version --json" >&2
    if [ -s "$version_error_log" ]; then
      cat "$version_error_log" >&2
    fi
    version_json=""
  fi
  rm -f "$version_error_log"

  TARGET_CONFIG_REVISION=""
  TARGET_NIXOS_VERSION=""
  if [ -n "$version_json" ]; then
    TARGET_CONFIG_REVISION="$(printf '%s\n' "$version_json" | version_json_field configurationRevision || true)"
    TARGET_NIXOS_VERSION="$(printf '%s\n' "$version_json" | version_json_field nixosVersion || true)"
  fi
}

verify_installed_revision() {
  capture_target_system_metadata

  if [ -z "$TARGET_SYSTEM_TOPLEVEL" ]; then
    echo "Error: could not resolve the installed USB system path."
    exit 1
  fi

  if [ -z "$TARGET_CONFIG_REVISION" ]; then
    echo "Error: could not read the installed USB configuration revision."
    exit 1
  fi

  if [ -n "$EXPECTED_CONFIG_REVISION" ]; then
    echo "Desired revision: $EXPECTED_CONFIG_REVISION"
  else
    echo "Desired revision: unavailable (flake evaluation did not return configurationRevision)"
  fi
  echo "Installed revision: $TARGET_CONFIG_REVISION"
  echo "Installed system: $TARGET_SYSTEM_TOPLEVEL"
  if [ -n "$TARGET_NIXOS_VERSION" ]; then
    echo "Installed NixOS version: $TARGET_NIXOS_VERSION"
  fi

  if [ -n "$EXPECTED_CONFIG_REVISION" ] && [ "$TARGET_CONFIG_REVISION" != "$EXPECTED_CONFIG_REVISION" ]; then
    echo "Error: installed USB revision does not match the expected flake revision."
    exit 1
  fi
}
