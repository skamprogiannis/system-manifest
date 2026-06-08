#!/usr/bin/env bash
# shellcheck disable=SC2034

usage() {
  cat <<EOF
Usage:
  sudo update-usb [--mode prebuild|in-place] [--in-place] [--force] [path-to-flake-dir]

Defaults:
  mode:      $DEFAULT_MODE
  flake dir: $PWD
  usb root:  $USB_ROOT_PART
  usb boot:  $USB_BOOT_DEV

Examples:
  sudo update-usb /path/to/system-manifest/main
  sudo update-usb --mode prebuild /path/to/system-manifest/main
  sudo update-usb --in-place /path/to/system-manifest/main
  sudo update-usb --force /path/to/system-manifest/main
EOF
}

parse_args() {
  local positional=()

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --mode)
        if [ "$#" -lt 2 ]; then
          echo "Error: --mode requires a value: prebuild or in-place."
          usage
          exit 1
        fi
        case "$2" in
          prebuild | in-place)
            MODE="$2"
            ;;
          *)
            echo "Error: invalid mode '$2'. Use prebuild or in-place."
            usage
            exit 1
            ;;
        esac
        shift 2
        ;;
      --mode=*)
        local mode_value="${1#*=}"
        case "$mode_value" in
          prebuild | in-place)
            MODE="$mode_value"
            ;;
          *)
            echo "Error: invalid mode '$mode_value'. Use prebuild or in-place."
            usage
            exit 1
            ;;
        esac
        shift
        ;;
      --in-place)
        MODE="in-place"
        shift
        ;;
      --force)
        FORCE_UPDATE=1
        shift
        ;;
      -h | --help)
        usage
        exit 0
        ;;
      --)
        shift
        while [ "$#" -gt 0 ]; do
          positional+=("$1")
          shift
        done
        ;;
      -*)
        echo "Error: unknown option '$1'."
        usage
        exit 1
        ;;
      *)
        positional+=("$1")
        shift
        ;;
    esac
  done

  if [ "${#positional[@]}" -gt 1 ]; then
    usage
    exit 1
  fi

  if [ "${#positional[@]}" -eq 1 ]; then
    FLAKE_DIR="${positional[0]}"
  fi
}
