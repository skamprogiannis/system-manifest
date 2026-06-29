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
      BEFORE=$(hyprctl -j activewindow | jq -r '.address')
      hyprctl dispatch movefocus $DIRECTION
      AFTER=$(hyprctl -j activewindow | jq -r '.address')

      if [ "$BEFORE" == "$AFTER" ] || [ "$BEFORE" == "null" ]; then
          CURR=$(hyprctl -j activeworkspace | jq '.id')
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

      active=$(hyprctl -j activewindow 2>/dev/null || true)
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
      set -euo pipefail

      usage() {
        cat <<'EOF'
      Usage: gsr-record [region|fullscreen|window|stop] [--no-audio] [--mic]

      Starts or stops screen recording with gpu-screen-recorder.
        region      interactively select an area to record
        fullscreen  record the focused monitor
        window      record the active window bounds
        stop        stop any active recording without starting a new one
        --mic       include the default microphone with desktop audio
      EOF
      }

      notify_recording() {
        local urgency="$1"
        local message="$2"
        printf 'Screen Recording: %s\n' "$message" >&2
        ${pkgs.libnotify}/bin/notify-send -u "$urgency" "Screen Recording" "$message" >/dev/null 2>&1 || true
      }

      focused_monitor() {
        hyprctl -j monitors | ${pkgs.jq}/bin/jq -r '
          (first(.[] | select(.focused == true)).name) // .[0].name // empty
        '
      }

      region_from_active_window() {
        hyprctl -j activewindow | ${pkgs.jq}/bin/jq -r '
          .at as $at
          | .size as $size
          | if ($at | length) >= 2 and ($size | length) >= 2 then
              "\($size[0])x\($size[1])+\($at[0])+\($at[1])"
            else
              empty
            end
        '
      }

      summarize_log() {
        [ -s "$LOGFILE" ] || return 0
        ${pkgs.gnused}/bin/sed -n '1,3p' "$LOGFILE" \
          | ${pkgs.coreutils}/bin/tr '\n' ' ' \
          | ${pkgs.gnused}/bin/sed 's/[[:space:]]\+/ /g; s/[[:space:]]*$//'
      }

      recorder_pid_matches() {
        local candidate="$1"
        local exe
        local cmdline
        exe=$(readlink -f "/proc/$candidate/exe" 2>/dev/null || true)
        [ "''${exe##*/}" = "gpu-screen-recorder" ] && return 0

        cmdline=$(${pkgs.coreutils}/bin/tr '\0' ' ' <"/proc/$candidate/cmdline" 2>/dev/null || true)
        [[ "$cmdline" == *gpu-screen-recorder* ]]
      }

      process_active() {
        local candidate="$1"
        local stat
        "$KILL_BIN" -0 "$candidate" 2>/dev/null || return 1
        stat=$(${pkgs.procps}/bin/ps -o stat= -p "$candidate" 2>/dev/null | ${pkgs.coreutils}/bin/tr -d '[:space:]')
        [ -n "$stat" ] || return 1
        [[ "$stat" != Z* ]]
      }

      find_recorder_pid() {
        if [ -f "$PIDFILE" ]; then
          local pid
          pid=$(cat "$PIDFILE" 2>/dev/null || true)
          if [[ "$pid" =~ ^[0-9]+$ ]] && process_active "$pid" && recorder_pid_matches "$pid"; then
            printf '%s\n' "$pid"
            return 0
          fi
        fi

        ${pkgs.procps}/bin/pgrep -u "$(${pkgs.coreutils}/bin/id -u)" -f '(^|/)gpu-screen-recorder( |$)' 2>/dev/null \
          | while IFS= read -r pid; do
              [ "$pid" != "$$" ] || continue
              if recorder_pid_matches "$pid"; then
                printf '%s\n' "$pid"
                return 0
              fi
            done
      }

      cleanup_state() {
        rm -f "$PIDFILE" "$OUTFILE_STATE" "$STATUSFILE"
      }

      stop_recording() {
        local pid
        pid=$(find_recorder_pid | ${pkgs.coreutils}/bin/head -n 1 || true)

        if [ -z "$pid" ]; then
          cleanup_state
          notify_recording low "No active recording."
          return 0
        fi

        "$KILL_BIN" -INT "$pid"

        for _ in $(${pkgs.coreutils}/bin/seq 1 100); do
          if ! process_active "$pid"; then
            break
          fi
          ${pkgs.coreutils}/bin/sleep 0.1
        done

        if process_active "$pid"; then
          notify_recording normal "Stop requested, but gpu-screen-recorder is still shutting down."
          return 1
        fi

        if [ -f "$OUTFILE_STATE" ]; then
          OUTFILE=$(cat "$OUTFILE_STATE")
          if [ -s "$OUTFILE" ]; then
            notify_recording low "Saved: $OUTFILE"
          else
            DETAIL=$(summarize_log || true)
            if [ -n "$DETAIL" ]; then
              notify_recording normal "Recorder stopped, but no file was saved. $DETAIL"
            else
              notify_recording normal "Recorder stopped, but no file was saved."
            fi
          fi
        else
          notify_recording low "Recording stopped."
        fi

        cleanup_state
      }

      MODE="region"
      AUDIO=1
      MIC=0
      if [ "''${1:-}" = "--help" ] || [ "''${1:-}" = "-h" ]; then
        usage
        exit 0
      fi
      if [ "$#" -gt 0 ] && [ "''${1#--}" = "$1" ]; then
        MODE="$1"
        shift
      fi

      case "$MODE" in
        region|fullscreen|window|stop) ;;
        *)
          echo "Error: unknown mode '$MODE'." >&2
          usage >&2
          exit 1
          ;;
      esac

      while [ "$#" -gt 0 ]; do
        case "$1" in
          --no-audio)
            AUDIO=0
            MIC=0
            ;;
          --mic)
            MIC=1
            ;;
          --help|-h)
            usage
            exit 0
            ;;
          *)
            echo "Error: unknown option $1." >&2
            usage >&2
            exit 1
            ;;
        esac
        shift
      done

      STATE_DIR="''${XDG_RUNTIME_DIR:-/tmp}/gsr-record"
      PIDFILE="$STATE_DIR/pid"
      STATUSFILE="$STATE_DIR/status"
      OUTFILE_STATE="$STATE_DIR/outfile"
      LOGFILE="$STATE_DIR/log"
      LOCKFILE="$STATE_DIR/lock"
      OUTDIR="$HOME/videos/screencasts"
      KILL_BIN="''${GSR_RECORD_KILL:-${pkgs.procps}/bin/kill}"
      mkdir -p "$STATE_DIR"
      mkdir -p "$OUTDIR"

      exec 9>"$LOCKFILE"
      if ! ${pkgs.util-linux}/bin/flock -n 9; then
        notify_recording normal "Selection or recorder state change already in progress. If selecting a region, press Escape to cancel it."
        exit 1
      fi

      if [ "$MODE" = "stop" ]; then
        stop_recording
        exit $?
      fi

      if [ -f "$PIDFILE" ]; then
        PID=$(cat "$PIDFILE")
        if [[ "$PID" =~ ^[0-9]+$ ]] && process_active "$PID" && recorder_pid_matches "$PID"; then
          stop_recording
          exit 0
        fi
        cleanup_state
      fi

      OUTFILE="$OUTDIR/screencast_$(date +%Y-%m-%d_%H-%M-%S).mp4"

      case "$MODE" in
        region)
          printf '%s\n' "selecting" > "$STATUSFILE"
          notify_recording low "Select a region. Escape cancels without saving."
          REGION=$(${pkgs.slurp}/bin/slurp -f '%wx%h+%x+%y' 2>/dev/null || true)
          if [ -z "$REGION" ]; then
            rm -f "$STATUSFILE"
            notify_recording low "Recording cancelled."
            exit 1
          fi
          WINDOW=region
          TARGET_ARGS=(-region "$REGION")
          ;;
        fullscreen)
          WINDOW=$(focused_monitor)
          if [ -z "$WINDOW" ]; then
            notify_recording normal "No monitor found to record."
            exit 1
          fi
          TARGET_ARGS=()
          ;;
        window)
          REGION=$(region_from_active_window)
          if [ -z "$REGION" ]; then
            notify_recording normal "No active window found to record."
            exit 1
          fi
          WINDOW=region
          TARGET_ARGS=(-region "$REGION")
          ;;
      esac

      AUDIO_ARGS=()
      if [ "$AUDIO" -eq 1 ]; then
        if [ "$MIC" -eq 1 ]; then
          AUDIO_ARGS=(-a "default_output|default_input")
        else
          AUDIO_ARGS=(-a default_output)
        fi
      fi

      printf '%s\n' "$OUTFILE" > "$OUTFILE_STATE"
      printf '%s\n' "recording" > "$STATUSFILE"
      : > "$LOGFILE"

      gpu-screen-recorder \
        -w "$WINDOW" \
        "''${TARGET_ARGS[@]}" \
        -f 60 \
        -c mp4 \
        "''${AUDIO_ARGS[@]}" \
        -o "$OUTFILE" \
        >"$LOGFILE" 2>&1 &

      PID=$!
      echo "$PID" > "$PIDFILE"
      ${pkgs.coreutils}/bin/sleep 1

      if ! process_active "$PID"; then
        DETAIL=$(summarize_log || true)
        rm -f "$PIDFILE" "$OUTFILE_STATE" "$STATUSFILE"
        if [ -n "$DETAIL" ]; then
          notify_recording normal "Failed to start: $DETAIL"
        else
          notify_recording normal "Failed to start recording."
        fi
        exit 1
      fi

      notify_recording low "Recording started (press the same shortcut again to stop). Saving to $OUTDIR"
    '')
  ];
}
