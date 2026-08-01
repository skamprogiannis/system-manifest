{...}: {
  programs.steam.enable = true;
  programs.gamemode.enable = true;

  systemd.tmpfiles.rules = [
    "d /home/stefan/games/SteamLibrary 0755 stefan users - -"
  ];
}
