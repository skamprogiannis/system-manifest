{
  config,
  weServiceConfig,
  ...
}: {
  programs.bash.initExtra = ''
    _wallpaper_engine_sync_complete() {
      local cur
      cur="''${COMP_WORDS[COMP_CWORD]}"
      COMPREPLY=($(compgen -W "--regen --list-subs --capture --capture-bad --help -h" -- "$cur"))
    }
    complete -F _wallpaper_engine_sync_complete wallpaper-engine-sync
  '';

  # Two identical WE services that alternate for seamless transitions.
  # When switching wallpapers, the idle slot starts first (its layer
  # surface renders on top), then the old slot is stopped — zero gap.
  systemd.user.services.linux-wallpaperengine-a = weServiceConfig;
  systemd.user.services.linux-wallpaperengine-b = weServiceConfig;

  systemd.user.services.dms.Service.ExecStartPost = "${config.home.profileDirectory}/bin/dms-restore-wallpaper";

  systemd.user.services.wallpaper-hook = {
    Unit = {
      Description = "DMS wallpaper sync hook";
      After = ["hyprland-session.target" "dms.service"];
      PartOf = ["hyprland-session.target"];
    };
    Service = {
      Type = "simple";
      ExecStart = "${config.home.profileDirectory}/bin/.wallpaper-hook";
      Restart = "on-failure";
      RestartSec = "2";
    };
    Install = {
      WantedBy = ["hyprland-session.target"];
    };
  };
}
