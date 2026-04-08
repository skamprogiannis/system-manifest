{
  config,
  pkgs,
  inputs,
  hostType ? null,
  ...
}: let
  spotifyDeviceName = if hostType == "usb" then "nixos-usb" else "nixos-desktop";
  spotifyServiceName = "spotify-player.service";
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
    set -eu

    real_player="${spotifyPlayerRawPkg}/bin/spotify_player"
    service_name="${spotifyServiceName}"
    auth_config_dir="${spotifyConfigDir}"
    credentials_file="${spotifyCacheDir}/credentials.json"
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

    stop_service() {
      ${pkgs.systemd}/bin/systemctl --user stop "$service_name" >/dev/null 2>&1 || true
    }

    ensure_authenticated() {
      if has_cached_credentials; then
        return 0
      fi

      stop_service
      echo "spotify_player: no cached Spotify credentials; starting interactive login" >&2
      "$real_player" -c "$auth_config_dir" authenticate
    }

    daemon_has_device() {
      devices="$("$real_player" -c ${spotifyDaemonConfigDir} get key devices 2>/dev/null || true)"
      printf '%s' "$devices" | ${pkgs.gnugrep}/bin/grep -Fq -- "${spotifyDeviceName}"
    }

    wait_for_device() {
      local attempts="$1"
      local attempt=0

      while [ "$attempt" -lt "$attempts" ]; do
        if daemon_has_device; then
          return 0
        fi

        attempt=$((attempt + 1))
        ${pkgs.coreutils}/bin/sleep 0.5
      done

      return 1
    }

    ensure_service_started() {
      ${pkgs.systemd}/bin/systemctl --user is-active --quiet "$service_name" && return 0
      ${pkgs.systemd}/bin/systemctl --user start "$service_name"
    }

    ensure_device_ready() {
      if wait_for_device "$initial_device_wait_attempts"; then
        return 0
      fi

      ${pkgs.systemd}/bin/systemctl --user restart "$service_name"
      wait_for_device "$retry_device_wait_attempts"
    }

    if [ "$#" -gt 0 ] && [ "$1" = "auth" ]; then
      shift
      set -- authenticate "$@"
    fi

    if [ "$#" -gt 0 ] && [ "$1" = "authenticate" ]; then
      stop_service
      exec_real_player "$@"
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
      echo "spotify_player: failed to start ${spotifyServiceName}; launching the client anyway" >&2
      exec_real_player "$@"
    fi

    if ! ensure_device_ready; then
      echo "spotify_player: ${spotifyDeviceName} did not become ready; launching the client anyway" >&2
    fi

    exec_real_player "$@"
  '';
in {
  # TUI config: no MPRIS or notifications. The daemon owns the local Connect
  # device so the client does not register a second same-name endpoint.
  home.file."${spotifyConfigDir}/app.toml".text = ''
    client_port = 8081
    login_redirect_uri = "http://127.0.0.1:8989/login"
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
