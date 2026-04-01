{
  config,
  pkgs,
  inputs,
  ...
}: let
  spotifyDeviceName = "nixos-desktop";
  spotifyServiceName = "spotify-player.service";
  spotifyPlayerRawPkg = inputs.spotify-player.defaultPackage.${pkgs.stdenv.hostPlatform.system};
  spotifyDaemonConfigDir = "${config.xdg.configHome}/spotify-player-daemon";
  spotifyDaemonArgs = "-c ${spotifyDaemonConfigDir} --daemon";
  spotifyPlayerPkg = pkgs.writeShellScriptBin "spotify_player" ''
    set -eu

    real_player="${spotifyPlayerRawPkg}/bin/spotify_player"
    service_name="${spotifyServiceName}"
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
        -h|--help|-V|--version|features|generate)
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

    if should_bypass_wrapper "$@"; then
      exec_real_player "$@"
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
  # TUI config: no MPRIS or notifications (daemon handles those)
  home.file."${config.xdg.configHome}/spotify-player/app.toml".text = ''
    client_port = 8081
    login_redirect_uri = "http://127.0.0.1:8989/login"
    enable_streaming = "DaemonOnly"
    playback_refresh_duration_in_ms = 2000
    enable_media_control = false
    enable_notify = false
    default_device = "${spotifyDeviceName}"

    [device]
    name = "${spotifyDeviceName}"
    device_type = "computer"
    volume = 90
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
    playback_refresh_duration_in_ms = 2000
    enable_notify = true
    notify_transient = true
    default_device = "${spotifyDeviceName}"

    [device]
    name = "${spotifyDeviceName}"
    device_type = "computer"
    volume = 90
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
