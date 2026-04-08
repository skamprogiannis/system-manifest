{pkgs, ...}: {
  home.packages = [
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

      # If the cached path is a WE directory, skip DMS restore — the
      # wallpaper-hook will handle WE startup and deferred capture.
      if [ -n "$wall" ] && [ -d "$wall" ]; then
        exit 0
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
  ];
}
