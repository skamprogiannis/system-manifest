{pkgs}:
pkgs.writeShellScriptBin "usb-host-scratch" ''
    set -eu

    mode_file="''${USB_HOST_SCRATCH_MODE_FILE:-/run/usb-host-scratch.mode}"
    repo_dir="''${USB_HOST_SCRATCH_REPO_DIR:-/nix/.host-scratch/repositories}"
    SYSTEMCTL="''${USB_HOST_SCRATCH_SYSTEMCTL:-${pkgs.systemd}/bin/systemctl}"
    SUDO="''${USB_HOST_SCRATCH_SUDO:-/run/wrappers/bin/sudo}"
    ID="''${USB_HOST_SCRATCH_ID:-${pkgs.coreutils}/bin/id}"

    usage() {
      ${pkgs.coreutils}/bin/cat <<'USAGE'
  Usage: usb-host-scratch [path|checkpoint|status]

  Commands:
    path        Print the encrypted host scratch repositories path.
    checkpoint  Copy cache, Codex, and Brave state back to the USB now.
    status      Show host scratch diagnostics and the last sync result.
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
      checkpoint)
        if [ ! -f "$mode_file" ] || ! ${pkgs.gnugrep}/bin/grep -qx "encrypted-host-scratch" "$mode_file"; then
          echo "usb-host-scratch: encrypted host scratch is not active" >&2
          exit 1
        fi
        echo "usb-host-scratch: checkpointing cache, Codex, and Brave to USB" >&2
        echo "usb-host-scratch: Docker state and repositories remain temporary and are not copied" >&2
        if [ "$("$ID" -u)" -eq 0 ]; then
          "$SYSTEMCTL" start --wait usb-host-scratch-checkpoint.service
        else
          "$SUDO" "$SYSTEMCTL" start --wait usb-host-scratch-checkpoint.service
        fi
        printf '%s\n' "USB host-scratch checkpoint completed."
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
