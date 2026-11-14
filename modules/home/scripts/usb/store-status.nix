{pkgs}:
pkgs.writeShellScriptBin "nixos-usb-store-status" ''
  set -eu
  # shellcheck disable=SC2034

  # TTY & NO_COLOR aware ANSI palette
  if [ -t 1 ] && [ "''${TERM:-}" != "dumb" ] && [ -z "''${NO_COLOR:-}" ]; then
    BOLD="\033[1m"
    GREEN="\033[0;32m"
    BLUE="\033[0;34m"
    YELLOW="\033[0;33m"
    RED="\033[0;31m"
    CYAN="\033[0;36m"
    NC="\033[0m"
  else
    BOLD=""
    GREEN=""
    BLUE=""
    YELLOW=""
    RED=""
    CYAN=""
    NC=""
  fi

  print_file() {
    local label="$1"
    local path="$2"

    if [ -t 1 ] && [ -n "$BOLD" ]; then
      printf '%b==> [%s]%b\n' "''${CYAN}''${BOLD}" "''${label^^}" "''${NC}"
    else
      printf '== %s ==\n' "$label"
    fi
    if [ -e "$path" ]; then
      ${pkgs.coreutils}/bin/cat "$path"
    else
      if [ -t 1 ] && [ -n "$BOLD" ]; then
        printf '  %bmissing:%b %s\n' "''${YELLOW}" "''${NC}" "$path"
      else
        printf 'missing: %s\n' "$path"
      fi
    fi
    printf '\n'
  }

  print_mount() {
    local path="$1"

    if ${pkgs.util-linux}/bin/findmnt -rn -M "$path" >/dev/null 2>&1; then
      if [ -t 1 ] && [ -n "$BOLD" ]; then
        printf '  %b[MOUNTED]%b   ' "''${GREEN}" "''${NC}"
        ${pkgs.util-linux}/bin/findmnt -rn -M "$path"
      else
        ${pkgs.util-linux}/bin/findmnt -M "$path"
      fi
    else
      if [ -t 1 ] && [ -n "$BOLD" ]; then
        printf '  %b[NOT MOUNTED]%b %s\n' "''${YELLOW}" "''${NC}" "$path"
      else
        printf 'not mounted: %s\n' "$path"
      fi
    fi
  }

  print_file "store mode" /run/nixos-usb-store-mode
  print_file "store diagnostics" /run/nixos-usb-store-diagnostics

  if ${pkgs.gnugrep}/bin/grep -qx 'fallback_reason=no-candidates' /run/nixos-usb-store-diagnostics 2>/dev/null; then
    printf '== current host partition inspection (not boot-time inventory) ==\n'
    printf '%s\n' 'BitLocker and other encrypted host partitions are not unlocked by host-auto.'
    printf '%s\n' 'Supported partitions must meet min_candidate_bytes above, then have that much free space and mount writable.'
    printf '%s\n' 'Small EFI and Windows recovery partitions cannot provide host scratch.'
    ${pkgs.util-linux}/bin/lsblk -p -o NAME,TYPE,RM,FSTYPE,SIZE || true
    printf '\n'
  fi

  if [ -e /run/nixos-usb-host-store-candidates ]; then
    print_file "host candidates" /run/nixos-usb-host-store-candidates
  fi

  if [ -s /run/nixos-usb-host-store-mount.err ]; then
    print_file "last host mount error" /run/nixos-usb-host-store-mount.err
  fi

  printf '== mounts ==\n'
  print_mount /nix/.ro-store
  print_mount /nix/.rw-store
  print_mount /nix/store
  print_mount /nix/.host-store
  print_mount /nix/.host-scratch
  print_mount /nix/.host-store-rw
  printf '\n'

  printf '== /nix mount tree ==\n'
  if ${pkgs.util-linux}/bin/findmnt -R /nix >/dev/null 2>&1; then
    ${pkgs.util-linux}/bin/findmnt -R /nix || true
  else
    printf 'not mounted: /nix\n'
  fi
  printf '\n'

  printf '== shutdown transport note ==\n'
  printf '%s\n' 'If shutdown pauses near 300s with cmd_age=300s, FAT boot-sector read failures, or "Maybe the USB cable is bad?", suspect USB port/cable/drive transport before mount ordering.'
  printf '\n'

  if ${pkgs.systemd}/bin/journalctl --version >/dev/null 2>&1; then
    printf '== initrd store services ==\n'
    ${pkgs.systemd}/bin/journalctl -b \
      -u initrd-usb-ram-store-prepare.service \
      -u initrd-usb-host-auto-store-prepare.service \
      --no-pager -n 80 || true
  fi
''
