{pkgs}:
pkgs.writeShellScriptBin "nixos-usb-store-status" ''
  set -eu

  print_file() {
    local label="$1"
    local path="$2"

    printf '== %s ==\n' "$label"
    if [ -e "$path" ]; then
      ${pkgs.coreutils}/bin/cat "$path"
    else
      printf 'missing: %s\n' "$path"
    fi
    printf '\n'
  }

  print_mount() {
    local path="$1"

    if ${pkgs.util-linux}/bin/findmnt -rn -M "$path" >/dev/null 2>&1; then
      ${pkgs.util-linux}/bin/findmnt -M "$path"
    else
      printf 'not mounted: %s\n' "$path"
    fi
  }

  print_file "store mode" /run/nixos-usb-store-mode
  print_file "store diagnostics" /run/nixos-usb-store-diagnostics

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

  if ${pkgs.systemd}/bin/journalctl --version >/dev/null 2>&1; then
    printf '== initrd store services ==\n'
    ${pkgs.systemd}/bin/journalctl -b \
      -u initrd-usb-ram-store-prepare.service \
      -u initrd-usb-host-auto-store-prepare.service \
      --no-pager -n 80 || true
  fi
''
