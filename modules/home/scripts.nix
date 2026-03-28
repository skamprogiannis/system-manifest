{ pkgs, ... }: {
  home.packages = [
    (pkgs.writeShellScriptBin "specify" ''
      exec ${pkgs.uv}/bin/uvx --from git+https://github.com/github/spec-kit.git specify "$@"
    '')
    (pkgs.writeShellScriptBin "copilot-sessions-sync" ''
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
          echo "Usage: copilot-sessions-sync [to-usb|from-usb]"
          sudo umount "$MOUNT"
          sudo ${pkgs.cryptsetup}/bin/cryptsetup luksClose "$MAPPER"
          exit 1
          ;;
      esac

      sudo umount "$MOUNT"
      sudo ${pkgs.cryptsetup}/bin/cryptsetup luksClose "$MAPPER"
      echo "Done."
    '')
    (pkgs.writeShellScriptBin "transmission-port-sync" ''
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
    (pkgs.writeShellScriptBin "dms-restore-wallpaper" ''
      set -eu

      CACHE_WALL="$HOME/.cache/current_wallpaper"
      FALLBACK_CACHE="$HOME/.cache/quickshell-last-wallpaper"

      for _ in $(seq 1 60); do
        if dms ipc wallpaper get >/dev/null 2>&1; then
          break
        fi
        sleep 0.25
      done

      wall=""
      if [ -s "$CACHE_WALL" ]; then
        wall=$(cat "$CACHE_WALL")
      elif [ -s "$FALLBACK_CACHE" ]; then
        wall=$(cat "$FALLBACK_CACHE")
      fi

      if [ -z "$wall" ] || [ ! -f "$wall" ]; then
        exit 0
      fi

      current=$(dms ipc wallpaper get 2>/dev/null || true)
      if [ "$current" = "$wall" ]; then
        exit 0
      fi

      for _ in $(seq 1 20); do
        dms ipc wallpaper set "$wall" >/dev/null 2>&1 || true
        sleep 0.5
        current=$(dms ipc wallpaper get 2>/dev/null || true)
        if [ "$current" = "$wall" ]; then
          exit 0
        fi
      done

      echo "dms-restore-wallpaper: failed to restore $wall" >&2
    '')
    (pkgs.writeShellScriptBin "wallpaper-library-sync" ''
      set -euo pipefail

      REPO_URL="''${WALLPAPER_REPO_URL:-}"
      REPO_BRANCH="''${WALLPAPER_REPO_BRANCH:-main}"
      REPO_DIR="''${WALLPAPER_REPO_DIR:-$HOME/wallpapers}"

      if [ -n "''${1:-}" ]; then
        REPO_URL="$1"
      fi

      if [ -n "$REPO_URL" ] && [ ! -d "$REPO_DIR/.git" ]; then
        mkdir -p "$(dirname "$REPO_DIR")"
        ${pkgs.git}/bin/git clone --depth 1 --branch "$REPO_BRANCH" "$REPO_URL" "$REPO_DIR"
      fi

      if [ ! -d "$REPO_DIR/.git" ]; then
        echo "No git repo found at $REPO_DIR and no repo URL provided."
        echo "Usage (first run): wallpaper-library-sync git@github.com:you/wallpapers.git"
        exit 1
      fi

      if ${pkgs.git}/bin/git -C "$REPO_DIR" remote get-url origin >/dev/null 2>&1; then
        ${pkgs.git}/bin/git -C "$REPO_DIR" fetch --depth 1 origin "$REPO_BRANCH"
        if ! ${pkgs.git}/bin/git -C "$REPO_DIR" show-ref --verify --quiet "refs/heads/$REPO_BRANCH"; then
          ${pkgs.git}/bin/git -C "$REPO_DIR" checkout -b "$REPO_BRANCH" "origin/$REPO_BRANCH"
        else
          ${pkgs.git}/bin/git -C "$REPO_DIR" checkout -q "$REPO_BRANCH"
        fi
        ${pkgs.git}/bin/git -C "$REPO_DIR" reset --hard "origin/$REPO_BRANCH"
      else
        echo "No origin remote configured at $REPO_DIR; skipping fetch/reset."
      fi

      mkdir -p "$REPO_DIR/.wallpaper-engine"
      touch "$REPO_DIR/.gitignore"
      if ! grep -qxF '.wallpaper-engine/' "$REPO_DIR/.gitignore"; then
        echo ".wallpaper-engine/" >> "$REPO_DIR/.gitignore"
        echo "Added .wallpaper-engine/ to $REPO_DIR/.gitignore"
      fi

      if ! grep -qxF '.DS_Store' "$REPO_DIR/.gitignore"; then
        echo ".DS_Store" >> "$REPO_DIR/.gitignore"
      fi
      if ! grep -qxF 'Thumbs.db' "$REPO_DIR/.gitignore"; then
        echo "Thumbs.db" >> "$REPO_DIR/.gitignore"
      fi

      echo "Synced static wallpapers repo at $REPO_DIR"
    '')
  ];
}
