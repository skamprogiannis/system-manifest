{ctx}: let
  inherit (ctx.pkgs) lib;
  desktop = ctx.self.nixosConfigurations.desktop.config;
  home = desktop.home-manager.users.stefan;
  aiServicesConfigured =
    desktop.services.open-webui.enable
    && desktop.services.searx.enable
    && desktop.systemd.services.open-webui.wantedBy == []
    && builtins.elem "multi-user.target" desktop.systemd.services.searx.wantedBy
    && desktop.services.open-webui.host == "127.0.0.1"
    && desktop.services.searx.settings.server.bind_address == "127.0.0.1"
    && !desktop.services.open-webui.openFirewall
    && !desktop.services.searx.openFirewall
    && !(builtins.elem "searx.service" desktop.systemd.services.open-webui.wants);
  hasCommand = name:
    builtins.any
    (package: lib.getName package == name)
    home.home.packages;
  hasLauncher =
    home.xdg.desktopEntries ? open-webui
    && home.xdg.desktopEntries.open-webui.exec == "ai-search launch"
    && !home.xdg.desktopEntries.open-webui.terminal;
  guiOnAllHosts =
    builtins.all
    (host:
      builtins.any (package: lib.getName package == "chatgpt-desktop")
      (ctx.homeConfig host).home.packages)
    ctx.registry.host;
in {
  host-configuration-contracts = assert lib.assertMsg ctx.spotifyPlayerRemoved
  "spotify_player and its service/auth migration must remain removed from every host.";
  assert lib.assertMsg (aiServicesConfigured && hasCommand "ai-search" && hasCommand "searxngctl" && hasLauncher)
  "Desktop AI search must use an on-demand Open WebUI launcher, an always-on local SearXNG, and independent commands.";
  assert lib.assertMsg guiOnAllHosts
  "The official ChatGPT desktop app with Codex must be installed on every host.";
    ctx.pkgs.runCommand "host-configuration-contracts-check" {} ''
      touch "$out"
    '';
}
