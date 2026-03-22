{
  config,
  pkgs,
  inputs,
  ...
}: let
  spotifyPlayerPkg = inputs.spotify-player.defaultPackage.${pkgs.stdenv.hostPlatform.system};
  spotifyDaemonConfigDir = "${config.xdg.configHome}/spotify-player-daemon";
  spotifyHealthcheck = pkgs.writeShellScript "spotify-player-healthcheck" ''
    set -eu

    if ! ${pkgs.systemd}/bin/systemctl --user is-active --quiet spotify-player.service; then
      exit 0
    fi

    probe_output="$(${spotifyPlayerPkg}/bin/spotify_player -c ${spotifyDaemonConfigDir} get key devices 2>&1)" && exit 0

    if printf '%s' "$probe_output" | ${pkgs.gnugrep}/bin/grep -q "400 Bad Request"; then
      ${pkgs.systemd}/bin/systemctl --user restart spotify-player.service
    fi
  '';
in {
  # TUI config: no MPRIS or notifications (daemon handles those)
  home.file."${config.xdg.configHome}/spotify-player/app.toml".text = ''
    client_port = 8081
    login_redirect_uri = "http://127.0.0.1:8989/login"
    enable_streaming = "DaemonOnly"
    enable_media_control = false
    enable_notify = false

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
      StartLimitIntervalSec = 300;
      StartLimitBurst = 3;
    };
    Service = {
      Type = "forking";
      ExecStartPre = "-${pkgs.psmisc}/bin/fuser -k 8081/tcp";
      ExecStart = "${spotifyPlayerPkg}/bin/spotify_player -c ${spotifyDaemonConfigDir} --daemon";
      Restart = "on-failure";
      RestartSec = "30s";
      TimeoutStopSec = "2s";
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
