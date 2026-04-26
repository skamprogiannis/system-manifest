{
  config,
  pkgs,
  inputs,
  lib,
  hostType ? "desktop",
  ...
}:
assert lib.assertMsg (builtins.elem hostType ["desktop" "usb"]) "hostType must be \"desktop\" or \"usb\".";
let
  spotifyDeviceName = if hostType == "usb" then "nixos-usb" else "nixos-desktop";
  spotifyServiceName = "spotify-player.service";
  spotifyUserClientId = "65b708073fc0480ea92a077233ca87bd";
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
    postPatch = (old.postPatch or "") + ''
      ${pkgs.python3}/bin/python3 ${spotifyPlayerClientPatch}
    '';
  });
  spotifyConfigDir = "${config.xdg.configHome}/spotify-player";
  spotifyCacheDir = "${config.xdg.cacheHome}/spotify-player";
  spotifyDaemonConfigDir = "${config.xdg.configHome}/spotify-player-daemon";
  spotifyDaemonArgs = "-c ${spotifyDaemonConfigDir} --daemon";
  spotifyPlayerPkg = pkgs.writeShellScriptBin "spotify_player" ''
    set -euo pipefail

    real_player="${spotifyPlayerRawPkg}/bin/spotify_player"
    service_name="${spotifyServiceName}"
    auth_config_dir="${spotifyConfigDir}"
    credentials_file="${spotifyCacheDir}/credentials.json"
    user_client_token_file="${spotifyCacheDir}/user_client_token.json"
    initial_device_wait_attempts=20
    retry_device_wait_attempts=10

    exec_real_player() {
      exec "$real_player" "$@"
    }

    should_bypass_wrapper() {
      if [ "$#" -eq 0 ]; then
        return 1
      fi

      case "$1" in
        -h|--help|-V|--version|authenticate|features|generate|help)
          return 0
          ;;
      esac

      for arg in "$@"; do
        case "$arg" in
          -d|--daemon)
            return 0
            ;;
        esac
      done

      return 1
    }

    is_known_subcommand() {
      case "$1" in
        get|playback|connect|like|authenticate|playlist|generate|search|features|lyrics|help)
          return 0
          ;;
      esac

      return 1
    }

    should_bootstrap_daemon() {
      if [ "$#" -eq 0 ]; then
        return 0
      fi

      case "$1" in
        get|playback|connect|like)
          return 0
          ;;
      esac

      return 1
    }

    has_cached_credentials() {
      [ -s "$credentials_file" ]
    }

    log_systemctl_warning() {
      local action="$1"
      local output="$2"

      case "$output" in
        *"not loaded"*|*"not found"*)
          return 0
          ;;
      esac

      if [ -n "$output" ]; then
        echo "spotify_player: warning: systemctl $action $service_name failed: $output" >&2
      fi
    }

    stop_service() {
      local output=""
      if ! output=$(${pkgs.systemd}/bin/systemctl --user stop "$service_name" 2>&1); then
        log_systemctl_warning "stop" "$output"
      fi
    }

    reset_failed_service() {
      local output=""
      if ! output=$(${pkgs.systemd}/bin/systemctl --user reset-failed "$service_name" 2>&1); then
        log_systemctl_warning "reset-failed" "$output"
      fi
    }

    service_has_failed() {
      ${pkgs.systemd}/bin/systemctl --user is-failed --quiet "$service_name"
    }

    clear_auth_cache() {
      rm -f "$credentials_file" "$user_client_token_file"
    }

    run_full_auth_flow() {
      stop_service
      reset_failed_service
      clear_auth_cache
      echo "spotify_player: starting interactive Spotify login" >&2
      # bootstrap_web_api_token is not needed here: clear_auth_cache already
      # removed the stale web API token, so the daemon will fetch a fresh one
      # on startup. Calling get-key-devices with no running daemon would trigger
      # a spurious second browser auth flow.
      "$real_player" -c "$auth_config_dir" authenticate
    }

    just_authenticated=0

    ensure_authenticated() {
      if has_cached_credentials; then
        return 0
      fi

      echo "spotify_player: no cached Spotify credentials; starting interactive login" >&2
      if run_full_auth_flow; then
        just_authenticated=1
        return 0
      fi
      return 1
    }

    recover_stale_auth() {
      if ! has_cached_credentials; then
        return 1
      fi

      stop_service
      reset_failed_service
      clear_auth_cache
      echo "spotify_player: cached Spotify tokens look stale; starting interactive login" >&2
      if run_full_auth_flow; then
        just_authenticated=1
        return 0
      fi
      return 1
    }

    daemon_socket_ready() {
      ${pkgs.iproute2}/bin/ss -tln 'sport = :8081' 2>/dev/null | ${pkgs.gnugrep}/bin/grep -q LISTEN
    }

    wait_for_device() {
      local attempts="$1"
      local attempt=0

      while [ "$attempt" -lt "$attempts" ]; do
        if daemon_socket_ready; then
          return 0
        fi

        # Short-circuit if the service has already crashed
        if service_has_failed; then
          return 1
        fi

        attempt=$((attempt + 1))
        ${pkgs.coreutils}/bin/sleep 0.5
      done

      return 1
    }

    ensure_service_started() {
      ${pkgs.systemd}/bin/systemctl --user is-active --quiet "$service_name" && return 0
      reset_failed_service
      ${pkgs.systemd}/bin/systemctl --user start "$service_name"
    }

    # Safe heuristic: a freshly-failed service with credentials present is most
    # likely an auth issue (Spotify rejected the refresh token). We never call
    # the binary here — `get key devices` would itself trigger an OAuth browser
    # tab when the web-API token is missing, causing a spurious second login.
    looks_like_auth_failure() {
      service_has_failed && has_cached_credentials
    }

    ensure_device_ready() {
      if wait_for_device "$initial_device_wait_attempts"; then
        return 0
      fi

      # Don't restart if it looks like an auth failure — the caller will re-auth.
      if looks_like_auth_failure; then
        return 1
      fi

      ${pkgs.systemd}/bin/systemctl --user restart "$service_name"
      wait_for_device "$retry_device_wait_attempts"
    }

    if [ "$#" -gt 0 ] && [ "$1" = "auth" ]; then
      shift
      set -- authenticate "$@"
    fi

    if [ "$#" -gt 0 ] && [ "$1" = "authenticate" ]; then
      if ! run_full_auth_flow; then
        echo "spotify_player: authentication failed" >&2
        exit 1
      fi
      exit 0
    fi

    if should_bypass_wrapper "$@"; then
      exec_real_player "$@"
    fi

    if [ "$#" -gt 0 ] && ! is_known_subcommand "$1"; then
      exec_real_player "$@"
    fi

    if ! should_bootstrap_daemon "$@"; then
      exec_real_player "$@"
    fi

    if ! ensure_authenticated; then
      echo "spotify_player: authentication failed" >&2
      exit 1
    fi

    if ! ensure_service_started; then
      if [ "$just_authenticated" -eq 0 ] && service_has_failed && recover_stale_auth && ensure_service_started; then
        :
      else
        echo "spotify_player: warning: ${spotifyServiceName} failed to start; using the client directly" >&2
        exec_real_player "$@"
      fi
    fi

    if ! ensure_device_ready; then
      if [ "$just_authenticated" -eq 0 ] && looks_like_auth_failure; then
        echo "spotify_player: Spotify login has expired — re-authenticating..." >&2
        if ! (recover_stale_auth && ensure_service_started && ensure_device_ready); then
          echo "spotify_player: re-authentication failed; run 'spotify_player authenticate' to log in again" >&2
          exit 1
        fi
      elif [ "$just_authenticated" -eq 0 ]; then
        echo "spotify_player: warning: ${spotifyDeviceName} did not become ready; continuing without daemon-backed device sync" >&2
      else
        echo "spotify_player: warning: ${spotifyDeviceName} did not become ready after fresh login; continuing anyway" >&2
      fi
    fi

    exec_real_player "$@"
  '';
in {
  # TUI config: no MPRIS or notifications. The daemon owns the local Connect
  # device so the client does not register a second same-name endpoint.
  home.file."${spotifyConfigDir}/app.toml".text = ''
    client_port = 8081
    login_redirect_uri = "http://127.0.0.1:8989/login"
    client_id = "${spotifyUserClientId}"
    enable_streaming = "DaemonOnly"
    playback_refresh_duration_in_ms = 0
    enable_media_control = false
    enable_notify = false
    default_device = "${spotifyDeviceName}"

    [device]
    name = "${spotifyDeviceName}"
    device_type = "computer"
    volume = 72
    bitrate = 320
    audio_cache = true
    normalization = false
  '';

  # Daemon config: MPRIS enabled so DMS media widget and media keys work
  home.file."${config.xdg.configHome}/spotify-player-daemon/app.toml".text = ''
    client_port = 8081
    login_redirect_uri = "http://127.0.0.1:8989/login"
    client_id = "${spotifyUserClientId}"
    enable_streaming = "DaemonOnly"
    enable_media_control = true
    playback_refresh_duration_in_ms = 0
    enable_notify = true
    notify_transient = true
    default_device = "${spotifyDeviceName}"

    [device]
    name = "${spotifyDeviceName}"
    device_type = "computer"
    volume = 72
    bitrate = 320
    audio_cache = true
    normalization = false
  '';

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
      After = [ "network-online.target" ];
      Wants = [ "network-online.target" ];
      StartLimitIntervalSec = 300;
      StartLimitBurst = 5;
    };
    Service = {
      Type = "forking";
      ExecStartPre = "-${pkgs.psmisc}/bin/fuser -k 8081/tcp";
      ExecStart = "${spotifyPlayerRawPkg}/bin/spotify_player ${spotifyDaemonArgs}";
      Restart = "on-failure";
      RestartSec = "15s";
      TimeoutStopSec = "5s";
    };
  };
}
