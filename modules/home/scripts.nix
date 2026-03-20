{ pkgs, ... }: {
  home.packages = [
    (pkgs.writeShellScriptBin "specify" ''
      exec ${pkgs.uv}/bin/uvx --from git+https://github.com/github/spec-kit.git specify "$@"
    '')
    (pkgs.writeShellScriptBin "sync-copilot-sessions" ''
      set -e
      MODE="''${1:-to-usb}"
      LUKS_DEVICE="/dev/disk/by-partlabel/NIXOS_USB_CRYPT"
      MAPPER="usb-sync-root"
      MOUNT="/mnt/usb-sync"
      LOCAL="$HOME/.copilot/session-state"
      REMOTE="$MOUNT/home/stefan/.copilot/session-state"

      if [ ! -e "$LUKS_DEVICE" ]; then
        echo "USB not found. Plug in the USB drive and try again."
        exit 1
      fi

      sudo ${pkgs.cryptsetup}/bin/cryptsetup luksOpen "$LUKS_DEVICE" "$MAPPER"
      sudo mkdir -p "$MOUNT"
      sudo mount "/dev/mapper/$MAPPER" "$MOUNT"
      sudo mkdir -p "$REMOTE"

      case "$MODE" in
        to-usb)
          echo "Syncing desktop → USB..."
          sudo ${pkgs.rsync}/bin/rsync -av --update "$LOCAL/" "$REMOTE/"
          ;;
        from-usb)
          echo "Syncing USB → desktop..."
          ${pkgs.rsync}/bin/rsync -av --update "$REMOTE/" "$LOCAL/"
          ;;
        *)
          echo "Usage: sync-copilot-sessions [to-usb|from-usb]"
          sudo umount "$MOUNT"
          sudo ${pkgs.cryptsetup}/bin/cryptsetup luksClose "$MAPPER"
          exit 1
          ;;
      esac

      sudo umount "$MOUNT"
      sudo ${pkgs.cryptsetup}/bin/cryptsetup luksClose "$MAPPER"
      echo "Done."
    '')
    (pkgs.writeShellScriptBin "sync-transmission-port" ''
      set -e
      CONFIG_DIR="$HOME/.config/fragments"
      SETTINGS_FILE="$CONFIG_DIR/settings.json"

      if [ -z "$1" ]; then
          echo "Usage: $0 <port>"
          exit 1
      fi
    '')
    (pkgs.writeShellScriptBin "hypr-nav" ''
      DIRECTION=$1
      BEFORE=$(hyprctl activewindow -j | jq -r '.address')
      hyprctl dispatch movefocus $DIRECTION
      AFTER=$(hyprctl activewindow -j | jq -r '.address')

      if [ "$BEFORE" == "$AFTER" ] || [ "$BEFORE" == "null" ]; then
          CURR=$(hyprctl activeworkspace -j | jq '.id')
          if [ "$DIRECTION" == "r" ]; then
              NEXT=$(( (CURR % 10) + 1 ))
              hyprctl dispatch workspace $NEXT
          elif [ "$DIRECTION" == "l" ]; then
              NEXT=$(( CURR - 1 ))
              [ $NEXT -lt 1 ] && NEXT=10
              hyprctl dispatch workspace $NEXT
          fi
      fi
    '')
    (pkgs.writeShellScriptBin "screenshot-path-copy" ''
      # Wraps dms screenshot to copy the FILE PATH to clipboard instead of the image
      dest=$(dms screenshot "$@" --no-clipboard --no-notify)
      if [ -n "$dest" ] && [ -f "$dest" ]; then
          echo -n "$dest" | ${pkgs.wl-clipboard}/bin/wl-copy
          ${pkgs.libnotify}/bin/notify-send -u low -i "$dest" "Screenshot" "Path copied: $dest"
      fi
    '')
    (pkgs.writeShellScriptBin "portal-yazi-filechooser" ''
      output="$1"
      [ -z "$output" ] && exit 1

      tmpdir=$(mktemp -d)
      chooser="$tmpdir/selection"
      ${pkgs.yazi}/bin/yazi --chooser-file "$chooser"
      status=$?
      if [ "$status" -eq 0 ] && [ -s "$chooser" ]; then
        cat "$chooser" > "$output"
      fi
      rm -rf "$tmpdir"
      exit "$status"
    '')
  ];
}
