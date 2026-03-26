{
  config,
  pkgs,
  inputs,
  ...
}: let
  spotifyPlayerPkg = inputs.spotify-player.defaultPackage.${pkgs.stdenv.hostPlatform.system};
  spotifyDaemonConfigDir = "${config.xdg.configHome}/spotify-player-daemon";
  spotifyDaemonArgs = "-c ${spotifyDaemonConfigDir} --daemon";
  spotifyDaemonPattern = "spotify_player ${spotifyDaemonArgs}";
  spotifyDaemonStart = pkgs.writeShellScript "spotify-player-daemon-start" ''
    set -eu

    daemon_pids="$(${pkgs.procps}/bin/pgrep -f -- "${spotifyDaemonPattern}" || true)"

    # Keep one daemon and terminate any extra instances to avoid API storms.
    if [ -n "$daemon_pids" ]; then
      keep_pid="$(printf '%s\n' "$daemon_pids" | ${pkgs.coreutils}/bin/head -n 1)"
      for pid in $daemon_pids; do
        if [ "$pid" != "$keep_pid" ]; then
          ${pkgs.coreutils}/bin/kill "$pid"
        fi
      done
      exit 0
    fi

    ${spotifyPlayerPkg}/bin/spotify_player ${spotifyDaemonArgs}
  '';
  spotifyHealthcheck = pkgs.writeShellScript "spotify-player-healthcheck" ''
    set -eu

    daemon_pids="$(${pkgs.procps}/bin/pgrep -f -- "${spotifyDaemonPattern}" || true)"
    if [ -z "$daemon_pids" ]; then
      ${pkgs.systemd}/bin/systemctl --user restart spotify-player.service
      exit 0
    fi

    if [ "$(printf '%s\n' "$daemon_pids" | ${pkgs.coreutils}/bin/wc -l)" -gt 1 ]; then
      ${pkgs.systemd}/bin/systemctl --user restart spotify-player.service
      exit 0
    fi

    probe_output="$(${spotifyPlayerPkg}/bin/spotify_player -c ${spotifyDaemonConfigDir} get key devices 2>&1)" && exit 0

    if printf '%s' "$probe_output" | ${pkgs.gnugrep}/bin/grep -Eq "400 Bad Request|429 Too Many Requests|status code 404|Connection failed|failed to send a Spotify API request"; then
      ${pkgs.systemd}/bin/systemctl --user restart spotify-player.service
      exit 0
    fi

    # Fallback: any failed daemon probe means we self-heal with a restart.
    ${pkgs.systemd}/bin/systemctl --user restart spotify-player.service
  '';
  spotifyPauseOnStart = pkgs.writeShellScript "spotify-player-pause-on-start" ''
    set -eu

    attempts=0
    while [ "$attempts" -lt 20 ]; do
      pause_output="$(${spotifyPlayerPkg}/bin/spotify_player -c ${spotifyDaemonConfigDir} playback pause 2>&1)" && exit 0

      # If nothing is playing (or API is transiently throttled), there is
      # nothing to pause and we should not block startup for long retries.
      if printf '%s' "$pause_output" | ${pkgs.gnugrep}/bin/grep -Eq "no playback found|status code 404|status code 429|Too Many Requests"; then
        exit 0
      fi
      attempts=$((attempts + 1))
      ${pkgs.coreutils}/bin/sleep 0.5
    done

    echo "spotify-player: could not force startup pause; daemon may still be initializing" >&2
  '';
in {
  # TUI config: no MPRIS or notifications (daemon handles those)
  home.file."${config.xdg.configHome}/spotify-player/app.toml".text = ''
    client_port = 8081
    login_redirect_uri = "http://127.0.0.1:8989/login"
    enable_streaming = "DaemonOnly"
    enable_media_control = false
    enable_notify = false
    default_device = "nixos-desktop"

    [device]
    name = "nixos-desktop"
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
    default_device = "nixos-desktop"

    [device]
    name = "nixos-desktop"
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
    };
    Service = {
      Type = "oneshot";
      ExecStart = spotifyDaemonStart;
      ExecStartPost = spotifyPauseOnStart;
      TimeoutStopSec = "5s";
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };

  systemd.user.services.spotify-player-healthcheck = {
    Unit = {
      Description = "Spotify Player Daemon Healthcheck";
      After = [ "spotify-player.service" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = spotifyHealthcheck;
    };
  };

  systemd.user.timers.spotify-player-healthcheck = {
    Unit = {
      Description = "Periodic spotify-player daemon healthcheck";
    };
    Timer = {
      OnStartupSec = "2m";
      OnUnitActiveSec = "5m";
      RandomizedDelaySec = "45s";
      Unit = "spotify-player-healthcheck.service";
    };
    Install = {
      WantedBy = [ "timers.target" ];
    };
  };
}
