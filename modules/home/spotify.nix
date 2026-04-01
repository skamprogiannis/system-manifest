{
  config,
  pkgs,
  inputs,
  ...
}: let
  spotifyDeviceName = "nixos-desktop";
  spotifyPlayerRawPkg = inputs.spotify-player.defaultPackage.${pkgs.stdenv.hostPlatform.system};
  spotifyDaemonConfigDir = "${config.xdg.configHome}/spotify-player-daemon";
  spotifyDaemonArgs = "-c ${spotifyDaemonConfigDir} --daemon";
  spotifyPlayerPkg = pkgs.writeShellScriptBin "spotify_player" ''
    set -eu

    real_player="${spotifyPlayerRawPkg}/bin/spotify_player"

    has_device() {
      devices="$("$real_player" -c ${spotifyDaemonConfigDir} get key devices 2>/dev/null || true)"
      printf '%s' "$devices" | ${pkgs.gnugrep}/bin/grep -q "${spotifyDeviceName}"
    }

    for arg in "$@"; do
      case "$arg" in
        -d|--daemon)
          exec "$real_player" "$@"
          ;;
      esac
    done

    if [ "$#" -gt 0 ]; then
      case "$1" in
        -h|--help|-V|--version|features|generate)
          exec "$real_player" "$@"
          ;;
      esac
    fi

    if ! ${pkgs.systemd}/bin/systemctl --user is-active --quiet spotify-player.service; then
      if ! ${pkgs.systemd}/bin/systemctl --user start spotify-player.service; then
        echo "spotify_player: failed to start spotify-player.service; launching the client anyway" >&2
        exec "$real_player" "$@"
      fi
    fi

    attempts=0
    while [ "$attempts" -lt 20 ]; do
      if has_device; then
        exec "$real_player" "$@"
      fi

      attempts=$((attempts + 1))
      ${pkgs.coreutils}/bin/sleep 0.5
    done

    if ${pkgs.systemd}/bin/systemctl --user restart spotify-player.service; then
      attempts=0
      while [ "$attempts" -lt 10 ]; do
        if has_device; then
          exec "$real_player" "$@"
        fi

        attempts=$((attempts + 1))
        ${pkgs.coreutils}/bin/sleep 0.5
      done
    fi

    exec "$real_player" "$@"
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

  # Daemon keeps the Spotify Connect device alive persistently so playback
  # never gets dropped even during network hiccups or TUI restarts.
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
