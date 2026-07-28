{
  pkgs,
  spotifyPackage,
}: let
  renderPolicy = import ../render-compat/policy.nix {
    inherit pkgs;
    name = "spotify";
    policyVersion = "spotify-gpu-fallback-v1";
    packageId = toString spotifyPackage;
    valueKey = "mode";
    allowedValues = ["software"];
  };
in
  pkgs.writeShellApplication {
    name = "spotify";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.libnotify
      pkgs.util-linux
    ];
    text = ''
      real_spotify="${spotifyPackage}/bin/spotify"
      notify_bin="${pkgs.libnotify}/bin/notify-send"
      healthy_seconds=30
      render_policy_fingerprint_file="/run/system-manifest/host-fingerprint"

      if [ "''${SYSTEM_MANIFEST_SPOTIFY_TEST_MODE:-}" = "1" ]; then
        real_spotify="''${SYSTEM_MANIFEST_SPOTIFY_REAL_BIN:?test mode requires SYSTEM_MANIFEST_SPOTIFY_REAL_BIN}"
        render_policy_fingerprint_file="''${SYSTEM_MANIFEST_SPOTIFY_FINGERPRINT_FILE:-$render_policy_fingerprint_file}"
        notify_bin="''${SYSTEM_MANIFEST_SPOTIFY_NOTIFY_BIN:-$notify_bin}"
        healthy_seconds="''${SYSTEM_MANIFEST_SPOTIFY_HEALTHY_SECONDS:-$healthy_seconds}"
      fi

      ${renderPolicy}

      state_home="''${XDG_STATE_HOME:-''${HOME:?HOME is required}/.local/state}"
      diagnostic_dir="$state_home/system-manifest/spotify"
      mkdir -p "$diagnostic_dir"
      chmod 0700 "$diagnostic_dir"
      last_stderr="$diagnostic_dir/last-stderr.log"

      invocation_dir="$(mktemp -d "''${XDG_RUNTIME_DIR:-''${TMPDIR:-/tmp}}/spotify-launcher.XXXXXX")"
      invocation_log="$invocation_dir/stderr.log"
      : > "$invocation_log"
      child_pid=""
      signaled_child_pid=""
      forwarded_signal=""
      forwarded_status=""
      spawning_child=0

      # ShellCheck does not follow functions invoked only through traps.
      # shellcheck disable=SC2329
      cleanup() {
        cp "$invocation_log" "$last_stderr" 2>/dev/null || true
        chmod 0600 "$last_stderr" 2>/dev/null || true
        rm -rf "$invocation_dir"
      }

      signal_child() {
        local signal="$1"
        if [ -n "$child_pid" ] && kill -0 "$child_pid" 2>/dev/null; then
          signaled_child_pid="$child_pid"
          kill -s "$signal" -- "-$child_pid" 2>/dev/null || kill -s "$signal" "$child_pid" 2>/dev/null || true
          sleep 2
          if kill -0 "$child_pid" 2>/dev/null; then
            kill -KILL -- "-$child_pid" 2>/dev/null || kill -KILL "$child_pid" 2>/dev/null || true
          fi
          return 0
        fi
        return 1
      }

      # shellcheck disable=SC2329
      forward_signal() {
        forwarded_signal="$1"
        forwarded_status="$2"
        if signal_child "$forwarded_signal"; then
          return
        fi
        if [ "$spawning_child" -eq 0 ]; then
          exit "$forwarded_status"
        fi
      }

      trap cleanup EXIT
      trap 'forward_signal INT 130' INT
      trap 'forward_signal TERM 143' TERM
      trap 'forward_signal QUIT 131' QUIT

      run_spotify() {
        local mode="$1"
        shift
        local attempt_log="$invocation_dir/$mode.stderr.log"
        local health_probe_lock="$invocation_dir/$mode.health.lock"
        local health_probe_sentinel="$invocation_dir/$mode.health.pending"
        local status

        if [ -n "$forwarded_status" ]; then
          return "$forwarded_status"
        fi

        : > "$attempt_log"
        spawning_child=1
        env \
          --default-signal=INT \
          --default-signal=TERM \
          --default-signal=QUIT \
          setsid --wait "$real_spotify" "$@" 2>"$attempt_log" &
        child_pid="$!"
        spawning_child=0

        if [ "$mode" = "software-fallback" ]; then
          touch "$health_probe_sentinel"
          (
            sleep "$healthy_seconds"
            if ! { exec 9>"$health_probe_lock"; } 2>/dev/null; then
              exit 0
            fi
            flock 9 || exit 0
            if [ -e "$health_probe_sentinel" ] && kill -0 "$child_pid" 2>/dev/null; then
              render_policy_write software || true
            fi
          ) &
        fi

        if [ -n "$forwarded_signal" ] && [ "$signaled_child_pid" != "$child_pid" ]; then
          signal_child "$forwarded_signal"
        fi

        while true; do
          if wait "$child_pid"; then
            status=0
          else
            status="$?"
          fi
          if ! kill -0 "$child_pid" 2>/dev/null; then
            break
          fi
        done
        child_pid=""
        if [ "$mode" = "software-fallback" ]; then
          exec 8>"$health_probe_lock"
          flock 8
          rm -f "$health_probe_sentinel"
          flock -u 8
          exec 8>&-
        fi

        {
          printf '== %s ==\n' "$mode"
          cat "$attempt_log"
        } >> "$invocation_log"
        cat "$attempt_log" >&2

        if [ -n "$forwarded_status" ]; then
          return "$forwarded_status"
        fi
        return "$status"
      }

      notify_packaging_failure() {
        echo "spotify: Mesa/glibc runtime mismatch; automatic GPU fallback is unsafe" >&2
        "$notify_bin" \
          --app-name=Spotify \
          "Spotify packaging error" \
          "Mesa and glibc are incompatible. GPU fallback was not attempted." \
          >/dev/null 2>&1 || true
      }

      has_disable_gpu=false
      for argument in "$@"; do
        if [ "$argument" = "--disable-gpu" ]; then
          has_disable_gpu=true
          break
        fi
      done

      if [ "$(render_policy_read || true)" = software ] && [ "$has_disable_gpu" = false ]; then
        if run_spotify software-cached --disable-gpu "$@"; then
          status=0
        else
          status="$?"
        fi
        if [ "$status" -ne 0 ] && [ -z "$forwarded_status" ]; then
          render_policy_clear
        fi
        exit "$status"
      fi

      if run_spotify normal "$@"; then
        status=0
      else
        status="$?"
      fi
      if [ "$status" -eq 0 ] || [ -n "$forwarded_status" ]; then
        exit "$status"
      fi

      normal_log="$invocation_dir/normal.stderr.log"
      if grep -Fq "MESA-LOADER" "$normal_log" \
        && grep -Eq "GLIBC[^[:space:]]*.*not found" "$normal_log"; then
        notify_packaging_failure
        exit "$status"
      fi

      if [ "$has_disable_gpu" = false ] \
        && grep -Fq "GPU process isn't usable" "$normal_log"; then
        if run_spotify software-fallback --disable-gpu "$@"; then
          fallback_status=0
        else
          fallback_status="$?"
        fi
        if [ "$fallback_status" -eq 0 ]; then
          render_policy_write software
        elif [ -z "$forwarded_status" ]; then
          render_policy_clear
        fi
        exit "$fallback_status"
      fi

      exit "$status"
    '';
  }
