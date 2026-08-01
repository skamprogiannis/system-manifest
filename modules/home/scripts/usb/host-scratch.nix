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
  Usage: usb-host-scratch [path|checkpoint [--include-cache]|status]

  Commands:
    path        Print the encrypted host scratch repositories path.
    checkpoint  Copy essential Codex and Brave state back to the USB now.
                Add --include-cache for an unbounded full ~/.cache copy.
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
        checkpoint_service=usb-host-scratch-checkpoint.service
        case "''${2:-}" in
          "")
            ;;
          --include-cache)
            checkpoint_service=usb-host-scratch-checkpoint-cache.service
            ;;
          *)
            usage >&2
            exit 2
            ;;
        esac
        if [ "$#" -gt 2 ]; then
          usage >&2
          exit 2
        fi
        echo "usb-host-scratch: checkpointing essential Codex and Brave state to USB" >&2
        if [ "$checkpoint_service" = usb-host-scratch-checkpoint-cache.service ]; then
          echo "usb-host-scratch: also checkpointing full user cache without a shutdown time budget" >&2
        fi
        echo "usb-host-scratch: Docker state, repositories, and the Steam library remain temporary and are not copied" >&2
        if [ "$("$ID" -u)" -eq 0 ]; then
          "$SYSTEMCTL" start --wait "$checkpoint_service"
        else
          "$SUDO" "$SYSTEMCTL" start --wait "$checkpoint_service"
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
