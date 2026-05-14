{
  config,
  pkgs,
  inputs,
  lib,
  hostType ? "desktop",
  ...
}:
assert lib.assertMsg (builtins.elem hostType ["desktop" "usb"]) "hostType must be \"desktop\" or \"usb\"."; let
  spotifyDeviceName =
    if hostType == "usb"
    then "nixos-usb"
    else "nixos-desktop";
  spotifyServiceName = "spotify-player.service";
  spotifySharedClientId = "65b708073fc0480ea92a077233ca87bd";
  spotifyPlayerClientPatch = pkgs.writeText "patch-spotify-player-client.py" ''
    import re
    from pathlib import Path

    path = Path("spotify_player/src/client/mod.rs")
    text = path.read_text()

    new_popup = """        #[cfg(feature = "streaming")]
        {
            if state.is_streaming_enabled() {
                let configs = config::get_config();
                let session = self.spotify.session().await;
                let local_device = Device {
                    id: session.device_id().to_string(),
                    name: configs.app_config.device.name.clone(),
                };

                // Only add if not already in the list (avoid duplicates)
                if !devices.iter().any(|d| d.id == local_device.id) {
                    devices.push(local_device);
                }
            }
        }
    """

    new_default = """        #[cfg(feature = "streaming")]
        {
            if configs.app_config.enable_streaming == config::StreamingType::Always {
                let session = self.spotify.session().await;
                devices.push((
                    configs.app_config.device.name.clone(),
                    session.device_id().to_string(),
                ));
            }
        }
    """

    popup_pattern = re.compile(
        r"""^[ \t]+#\[cfg\(feature = "streaming"\)\]\n"""
        r"""[ \t]+\{\n"""
        r"""[ \t]+let configs = config::get_config\(\);\n"""
        r"""[ \t]+let session = self\.spotify\.session\(\)\.await;\n"""
        r"""[ \t]+let local_device = Device \{\n"""
        r"""[ \t]+id: session\.device_id\(\)\.to_string\(\),\n"""
        r"""[ \t]+name: configs\.app_config\.device\.name\.clone\(\),\n"""
        r"""[ \t]+\};\n\n"""
        r"""[ \t]+// Only add if not already in the list \(avoid duplicates\)\n"""
        r"""[ \t]+if !devices\.iter\(\)\.any\(\|d\| d\.id == local_device\.id\) \{\n"""
        r"""[ \t]+devices\.push\(local_device\);\n"""
        r"""[ \t]+\}\n"""
        r"""[ \t]+\}\n""",
        re.MULTILINE,
    )
    default_pattern = re.compile(
        r"""^[ \t]+#\[cfg\(feature = "streaming"\)\]\n"""
        r"""[ \t]+\{\n"""
        r"""[ \t]+let session = self\.spotify\.session\(\)\.await;\n"""
        r"""[ \t]+devices\.push\(\(\n"""
        r"""[ \t]+configs\.app_config\.device\.name\.clone\(\),\n"""
        r"""[ \t]+session\.device_id\(\)\.to_string\(\),\n"""
        r"""[ \t]+\)\);\n"""
        r"""[ \t]+\}\n""",
        re.MULTILINE,
    )

    text, popup_count = popup_pattern.subn(new_popup, text, count=1)
    if popup_count != 1:
        raise SystemExit("spotify-player popup device block not found")
    text, default_count = default_pattern.subn(new_default, text, count=1)
    if default_count != 1:
        raise SystemExit("spotify-player default device block not found")
    path.write_text(text)
  '';
  spotifyPlayerUpstreamPkg = inputs.spotify-player.defaultPackage.${pkgs.stdenv.hostPlatform.system};
  spotifyPlayerRawPkg = spotifyPlayerUpstreamPkg.overrideAttrs (old: {
    postPatch =
      (old.postPatch or "")
      + ''
        ${pkgs.python3}/bin/python3 ${spotifyPlayerClientPatch}
      '';
  });
  spotifyConfigDir = "${config.xdg.configHome}/spotify-player";
  spotifyCacheDir = "${config.xdg.cacheHome}/spotify-player";
  spotifyDaemonConfigDir = "${config.xdg.configHome}/spotify-player-daemon";
  spotifyDaemonArgs = "-c ${spotifyDaemonConfigDir} --daemon";
  spotifyClientIdFile = "${spotifyConfigDir}/client_id";
  spotifyClientIdStamp = "${config.xdg.stateHome}/system-manifest/spotify-client-id-v1";
  spotifyClientIdCommand = pkgs.writeShellScript "spotify-player-client-id" ''
    set -euo pipefail

    client_id_file="${spotifyClientIdFile}"
    if [ -s "$client_id_file" ]; then
      exec ${pkgs.coreutils}/bin/cat "$client_id_file"
    fi

    printf '%s\n' "${spotifySharedClientId}"
  '';

  # Subcommands that need the daemon running. Everything else (and any
  # unknown command/flag) is passed straight through to the real binary.
  appTomlBase = ''
    client_port = 8081
    login_redirect_uri = "http://127.0.0.1:8989/login"
    client_id_command = { command = "${spotifyClientIdCommand}", args = [] }
    enable_streaming = "DaemonOnly"
    app_refresh_duration_in_ms = 0
    playback_refresh_duration_in_ms = 0
    default_device = "${spotifyDeviceName}"

    [device]
    name = "${spotifyDeviceName}"
    device_type = "computer"
    volume = 72
    bitrate = 320
    audio_cache = true
    normalization = false
  '';

  spotifyPlayerPkg = pkgs.writeShellScriptBin "spotify_player" ''
    set -euo pipefail

    real_player="${spotifyPlayerRawPkg}/bin/spotify_player"
    service="${spotifyServiceName}"
    cache_dir="${spotifyCacheDir}"
    client_id_file="${spotifyClientIdFile}"
    client_id_stamp="${spotifyClientIdStamp}"
    creds="${spotifyCacheDir}/credentials.json"
    web_token="${spotifyCacheDir}/user_client_token.json"
    auth_attempted=0
    shopt -s nullglob

    effective_client_id() {
      "${spotifyClientIdCommand}"
    }

    sync_client_id_cache() {
      local current_id previous_id
      current_id="$(effective_client_id)"
      mkdir -p "$(${pkgs.coreutils}/bin/dirname "$client_id_stamp")"

      if [ -s "$client_id_stamp" ]; then
        previous_id="$(<"$client_id_stamp")"
        if [ "$previous_id" != "$current_id" ]; then
          rm -f "$creds" "$web_token"
          echo "spotify_player: Spotify client ID changed; clearing cached auth before re-authenticating" >&2
        fi
      fi

      printf '%s\n' "$current_id" > "$client_id_stamp"
    }

    needs_daemon() {
      [ "$#" -eq 0 ] && return 0
      case "$1" in
        playback|connect|like|get) return 0 ;;
      esac
      return 1
    }

    service_has_failed() {
      ${pkgs.systemd}/bin/systemctl --user is-failed --quiet "$service"
    }

    start_service() {
      ${pkgs.systemd}/bin/systemctl --user reset-failed "$service" >/dev/null 2>&1 || true
      ${pkgs.systemd}/bin/systemctl --user start "$service" >/dev/null 2>&1
    }

    wait_for_daemon() {
      for _ in $(${pkgs.coreutils}/bin/seq 1 20); do
        if ${pkgs.iproute2}/bin/ss -tln 'sport = :8081' 2>/dev/null | ${pkgs.gnugrep}/bin/grep -q LISTEN; then
          return 0
        fi

        if service_has_failed; then
          return 2
        fi

        ${pkgs.coreutils}/bin/sleep 0.5
      done

      return 1
    }

    latest_spotify_log() {
      local log latest=""
      local logs=("$cache_dir"/spotify-player-*.log)

      if [ "''${#logs[@]}" -eq 0 ] || [ ! -e "''${logs[0]}" ]; then
        return 1
      fi

      for log in "''${logs[@]}"; do
        if [ -z "$latest" ] || [ "$log" -nt "$latest" ]; then
          latest="$log"
        fi
      done

      printf '%s\n' "$latest"
    }

    daemon_log_has_rate_limit() {
      local latest_log
      latest_log="$(latest_spotify_log)" || return 1
      ${pkgs.gnugrep}/bin/grep -Eq 'status code 429 Too Many Requests|"status":[[:space:]]*429|"message":[[:space:]]*"API rate limit exceeded"' "$latest_log"
    }

    run_auth() {
      ${pkgs.systemd}/bin/systemctl --user stop "$service" >/dev/null 2>&1 || true
      ${pkgs.systemd}/bin/systemctl --user reset-failed "$service" >/dev/null 2>&1 || true
      rm -f "$creds" "$web_token"
      echo "spotify_player: starting interactive Spotify login" >&2
      "$real_player" -c "${spotifyConfigDir}" authenticate
    }

    sync_client_id_cache

    # Explicit auth subcommand
    if [ "$#" -gt 0 ] && { [ "$1" = "auth" ] || [ "$1" = "authenticate" ]; }; then
      run_auth
      exit
    fi

    # Pass-through for anything that doesn't need the daemon
    if ! needs_daemon "$@"; then
      exec "$real_player" "$@"
    fi

    # Bootstrap credentials on first run
    if [ ! -s "$creds" ]; then
      echo "spotify_player: no cached Spotify credentials; starting interactive login" >&2
      run_auth
      auth_attempted=1
    fi

    # If cached credentials have gone stale, the daemon dies quickly with a
    # 400 refresh-token failure. Recover once by clearing the cached login and
    # re-running the interactive auth flow, but never probe with a CLI command
    # that could itself launch another browser tab.
    daemon_status=0
    if ! start_service; then
      echo "spotify_player: warning: $service failed to start; if Spotify rejects the cached login, run 'spotify_player authenticate'" >&2
    fi

    wait_for_daemon || daemon_status=$?

    if [ "$daemon_status" -eq 2 ] && [ "$auth_attempted" -eq 0 ] && [ -s "$creds" ]; then
      echo "spotify_player: cached Spotify login expired; re-authenticating..." >&2
      run_auth
      auth_attempted=1
      daemon_status=0

      if ! start_service; then
        echo "spotify_player: warning: $service failed to start after re-authentication" >&2
      fi

      wait_for_daemon || daemon_status=$?
    fi

    if [ "$daemon_status" -eq 1 ]; then
      echo "spotify_player: warning: $service did not become ready; the TUI may stay stuck in loading" >&2
    elif [ "$daemon_status" -eq 2 ]; then
      echo "spotify_player: warning: $service still fails after re-authentication; the TUI may stay stuck in loading" >&2
    fi

    if daemon_log_has_rate_limit; then
      if [ -s "$client_id_file" ]; then
        echo "spotify_player: warning: Spotify Web API is rate-limited for the current client ID; wait for Spotify's Retry-After window, then run 'spotify_player authenticate' if the TUI stays blank" >&2
      else
        echo "spotify_player: warning: Spotify Web API is rate-limited for the shared client ID; add your own Spotify app client ID to '$client_id_file' and rerun 'spotify_player authenticate' if the TUI stays blank" >&2
      fi
    fi

    exec "$real_player" "$@"
  '';
in {
  # TUI config: no MPRIS or notifications. The daemon owns the local Connect
  # device so the client does not register a second same-name endpoint.
  home.file."${spotifyConfigDir}/app.toml".text = ''
    enable_media_control = false
    enable_notify = false
    ${appTomlBase}'';

  # Daemon config: MPRIS enabled so DMS media widget and media keys work.
  home.file."${config.xdg.configHome}/spotify-player-daemon/app.toml".text = ''
    enable_media_control = true
    enable_notify = true
    notify_transient = true
    ${appTomlBase}'';

  programs.spotify-player = {
    enable = true;
    package = spotifyPlayerPkg;
  };

  # Keep the user-facing wrapper and the background daemon separate: the
  # wrapper bootstraps the service on demand, while systemd must launch the
  # raw binary directly to avoid recursive self-start.
  systemd.user.services.spotify-player = {
    Unit = {
      Description = "Spotify Player Daemon";
      After = ["network-online.target"];
      Wants = ["network-online.target"];
      StartLimitIntervalSec = 300;
      StartLimitBurst = 5;
    };
    Service = {
      Type = "forking";
      ExecStart = "${spotifyPlayerRawPkg}/bin/spotify_player ${spotifyDaemonArgs}";
      Restart = "on-failure";
      RestartSec = "15s";
      TimeoutStopSec = "5s";
    };
  };
}
