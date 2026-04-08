{pkgs, ...}: {
  home.packages = [
    (pkgs.writeShellScriptBin "transmission-port-sync" ''
      set -euo pipefail

      CONFIG_DIR="$HOME/.config/fragments"
      SETTINGS_FILE="$CONFIG_DIR/settings.json"
      RPC_ENDPOINT="127.0.0.1:9091"

      usage() {
        echo "Usage: $0 <peer-port>"
      }

      if [ "$#" -ne 1 ]; then
        usage
        exit 1
      fi

      if ! [[ "$1" =~ ^[0-9]+$ ]] || [ "$1" -lt 1 ] || [ "$1" -gt 65535 ]; then
        echo "Error: port must be an integer between 1 and 65535."
        exit 1
      fi

      PORT="$1"

      if [ ! -f "$SETTINGS_FILE" ]; then
        echo "Error: Transmission settings not found at $SETTINGS_FILE"
        echo "Start transmission-daemon once first so it writes its config."
        exit 1
      fi

      tmp="$(${pkgs.coreutils}/bin/mktemp)"
      trap 'rm -f "$tmp"' EXIT

      # Keep Transmission's peer port aligned with the forwarded VPN port.
      ${pkgs.jq}/bin/jq --argjson port "$PORT" '
        .["peer-port"] = $port
        | .["peer-port-random-on-start"] = false
      ' "$SETTINGS_FILE" > "$tmp"
      ${pkgs.coreutils}/bin/mv "$tmp" "$SETTINGS_FILE"

      if ${pkgs.systemd}/bin/systemctl --user --quiet is-active transmission-daemon.service; then
        if ${pkgs.transmission_4}/bin/transmission-remote "$RPC_ENDPOINT" --port "$PORT" >/dev/null 2>&1; then
          echo "Updated live Transmission peer port to $PORT."
        else
          ${pkgs.systemd}/bin/systemctl --user restart transmission-daemon.service
          echo "Updated Transmission peer port to $PORT and restarted transmission-daemon."
        fi
      else
        echo "Stored Transmission peer port $PORT in settings.json."
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
    (pkgs.writeShellScriptBin "hypr-quit-active" ''
      set -euo pipefail

      active=$(hyprctl activewindow -j 2>/dev/null || true)
      pid=$(printf '%s' "$active" | ${pkgs.jq}/bin/jq -r '.pid // empty')
      app_class=$(printf '%s' "$active" | ${pkgs.jq}/bin/jq -r '.class // empty')
      app_title=$(printf '%s' "$active" | ${pkgs.jq}/bin/jq -r '.title // empty')

      if [ -z "$pid" ] || [ "$pid" = "null" ]; then
        ${pkgs.libnotify}/bin/notify-send -u low "Quit active app" "No active window to quit."
        exit 1
      fi

      resolve_root_pid() {
        local candidate="$1"
        local exe
        exe=$(readlink -f "/proc/$candidate/exe" 2>/dev/null || true)
        [ -n "$exe" ] || {
          printf '%s\n' "$candidate"
          return
        }

        while true; do
          local ppid
          local parent_exe

          ppid=$(${pkgs.procps}/bin/ps -o ppid= -p "$candidate" 2>/dev/null | ${pkgs.coreutils}/bin/tr -d '[:space:]')
          [ -n "$ppid" ] || break
          [ "$ppid" -le 1 ] && break

          parent_exe=$(readlink -f "/proc/$ppid/exe" 2>/dev/null || true)
          [ "$parent_exe" = "$exe" ] || break

          candidate="$ppid"
        done

        printf '%s\n' "$candidate"
      }

      target_pid=$(resolve_root_pid "$pid")
      label="$app_class"
      [ -n "$label" ] || label="$app_title"
      [ -n "$label" ] || label="PID $target_pid"

      kill -TERM "$target_pid"

      for _ in $(${pkgs.coreutils}/bin/seq 1 20); do
        if ! kill -0 "$target_pid" 2>/dev/null; then
          exit 0
        fi
        ${pkgs.coreutils}/bin/sleep 0.1
      done

      ${pkgs.libnotify}/bin/notify-send -u low "Quit active app" "Force killing $label"
      kill -KILL "$target_pid"
    '')
    (pkgs.writeShellScriptBin "screenshot-path-copy" ''
      dest=$(dms screenshot "$@" --dir ~/pictures/screenshots --no-clipboard --no-notify)
      if [ -n "$dest" ] && [ -f "$dest" ]; then
          echo -n "$dest" | ${pkgs.wl-clipboard}/bin/wl-copy
          ${pkgs.libnotify}/bin/notify-send -u low -i "$dest" "Screenshot" "Path copied: $dest"
      fi
    '')
    (pkgs.writeShellScriptBin "gsr-record" ''
      MODE="''${1:-region}"
      AUDIO=1
      [ "''${2:-}" = "--no-audio" ] && AUDIO=0

      PIDFILE="''${XDG_RUNTIME_DIR:-/tmp}/gsr-record.pid"
      OUTDIR="$HOME/videos/screencasts"
      mkdir -p "$OUTDIR"

      if [ -f "$PIDFILE" ]; then
        PID=$(cat "$PIDFILE")
        if kill -0 "$PID" 2>/dev/null; then
          kill -INT "$PID"
          ${pkgs.libnotify}/bin/notify-send -u low "Screen Recording" "Recording stopped"
          rm -f "$PIDFILE"
          exit 0
        fi
        rm -f "$PIDFILE"
      fi

      OUTFILE="$OUTDIR/screencast_$(date +%Y-%m-%d_%H-%M-%S).mp4"

      case "$MODE" in
        region)     WINDOW=region ;;
        fullscreen) WINDOW=$(hyprctl monitors -j | ${pkgs.jq}/bin/jq -r '.[0].name') ;;
        window)     WINDOW=focused ;;
        *)          WINDOW=region ;;
      esac

      AUDIO_ARGS=()
      [ "$AUDIO" -eq 1 ] && AUDIO_ARGS=(-a default_output)

      gpu-screen-recorder -w "$WINDOW" -f 60 -c mp4 "''${AUDIO_ARGS[@]}" -o "$OUTFILE" &
      echo $! > "$PIDFILE"
      ${pkgs.libnotify}/bin/notify-send -u low "Screen Recording" "Recording started (press again to stop)"
    '')
  ];
}
