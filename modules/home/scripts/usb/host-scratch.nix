{pkgs}:
pkgs.writeShellScriptBin "usb-host-scratch" ''
  set -eu

  mode_file=/run/usb-host-scratch.mode
  repo_dir="/nix/.host-scratch/repositories"

  usage() {
    ${pkgs.coreutils}/bin/cat <<'USAGE'
Usage: usb-host-scratch [path|status]

Commands:
  path    Print the encrypted host scratch repositories path.
  status  Show host scratch diagnostics.
USAGE
  }

  cmd="''${1:-path}"

  case "$cmd" in
    path|repositories)
      if [ ! -f "$mode_file" ] || ! ${pkgs.gnugrep}/bin/grep -qx "encrypted-host-scratch" "$mode_file"; then
        echo "usb-host-scratch: encrypted host scratch is not active" >&2
        exit 1
      fi
      ${pkgs.coreutils}/bin/mkdir -p "$repo_dir"
      printf '%s\n' "$repo_dir"
      ;;
    status)
      exec nixos-usb-host-scratch-status
      ;;
    -h|--help|help)
      usage
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
''
