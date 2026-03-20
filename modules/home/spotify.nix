{
  config,
  pkgs,
  inputs,
  ...
}: {
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
    package = inputs.spotify-player.defaultPackage.${pkgs.stdenv.hostPlatform.system};
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
      ExecStart = "${inputs.spotify-player.defaultPackage.${pkgs.stdenv.hostPlatform.system}}/bin/spotify_player -c ${config.xdg.configHome}/spotify-player-daemon --daemon";
      Restart = "on-failure";
      RestartSec = "30s";
      TimeoutStopSec = "2s";
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };
}
