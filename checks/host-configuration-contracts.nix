{ctx}: let
  inherit (ctx.pkgs) lib;
  desktop = ctx.self.nixosConfigurations.desktop.config;
  aiSearchIsManual =
    desktop.services.open-webui.enable
    && desktop.services.searx.enable
    && desktop.systemd.services.open-webui.wantedBy == []
    && desktop.systemd.services.searx.wantedBy == []
    && desktop.services.open-webui.host == "127.0.0.1"
    && desktop.services.searx.settings.server.bind_address == "127.0.0.1"
    && !desktop.services.open-webui.openFirewall
    && !desktop.services.searx.openFirewall;
  hasAiSearchCommand = builtins.any
    (package: lib.getName package == "ai-search")
    desktop.home-manager.users.stefan.home.packages;
in {
  host-configuration-contracts = assert lib.assertMsg ctx.spotifyPlayerRemoved
  "spotify_player and its service/auth migration must remain removed from every host.";
  assert lib.assertMsg (aiSearchIsManual && hasAiSearchCommand)
  "Desktop AI search must be loopback-only, manually started, and expose the ai-search command.";
    ctx.pkgs.runCommand "host-configuration-contracts-check" {} ''
      touch "$out"
    '';
}
