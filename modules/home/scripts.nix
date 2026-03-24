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
    (pkgs.writeShellScriptBin "sync-static-wallpapers" ''
      set -euo pipefail

      REPO_URL="''${WALLPAPER_REPO_URL:-}"
      REPO_BRANCH="''${WALLPAPER_REPO_BRANCH:-main}"
      REPO_SUBDIR="''${WALLPAPER_REPO_SUBDIR:-.}"
      REPO_CHECKOUT="$HOME/repositories/static-wallpapers"
      DEST_DIR="$HOME/wallpapers/static"

      if [ -n "''${1:-}" ]; then
        REPO_URL="$1"
      fi

      if [ -z "$REPO_URL" ]; then
        echo "Set WALLPAPER_REPO_URL or pass a repo URL as first argument."
        echo "Example: sync-static-wallpapers git@github.com:you/wallpapers.git"
        exit 1
      fi

      if [ -d "$REPO_CHECKOUT/.git" ]; then
        ${pkgs.git}/bin/git -C "$REPO_CHECKOUT" fetch --depth 1 origin "$REPO_BRANCH"
        if ! ${pkgs.git}/bin/git -C "$REPO_CHECKOUT" show-ref --verify --quiet "refs/heads/$REPO_BRANCH"; then
          ${pkgs.git}/bin/git -C "$REPO_CHECKOUT" checkout -b "$REPO_BRANCH" "origin/$REPO_BRANCH"
        else
          ${pkgs.git}/bin/git -C "$REPO_CHECKOUT" checkout -q "$REPO_BRANCH"
        fi
        ${pkgs.git}/bin/git -C "$REPO_CHECKOUT" reset --hard "origin/$REPO_BRANCH"
      else
        mkdir -p "$(dirname "$REPO_CHECKOUT")"
        ${pkgs.git}/bin/git clone --depth 1 --branch "$REPO_BRANCH" "$REPO_URL" "$REPO_CHECKOUT"
      fi

      SRC_DIR="$REPO_CHECKOUT/$REPO_SUBDIR"
      if [ ! -d "$SRC_DIR" ]; then
        echo "Source subdir not found in repo: $SRC_DIR"
        exit 1
      fi

      mkdir -p "$DEST_DIR"
      ${pkgs.rsync}/bin/rsync -av --delete --exclude '.git' "$SRC_DIR"/ "$DEST_DIR"/
      echo "Synced static wallpapers into $DEST_DIR"
    '')
  ];
}
