#!/usr/bin/env bash
# shellcheck disable=SC2034

usage() {
  cat <<EOF
Usage:
  sudo update-usb [-v|--verbose] [--in-place] [--force] [path-to-flake-dir]

Defaults:
  mode:      $DEFAULT_MODE
  flake dir: $PWD
  usb root:  $USB_ROOT_PART
  usb boot:  $USB_BOOT_DEV

Examples:
  sudo update-usb /path/to/system-manifest/main
  sudo update-usb --verbose /path/to/system-manifest/main
  sudo update-usb --in-place /path/to/system-manifest/main
  sudo update-usb --force /path/to/system-manifest/main
EOF
}

parse_args() {
  local positional=()

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --in-place)
        MODE="in-place"
        shift
        ;;
      --force)
        FORCE_UPDATE=1
        shift
        ;;
      -v | --verbose)
        VERBOSE=1
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
