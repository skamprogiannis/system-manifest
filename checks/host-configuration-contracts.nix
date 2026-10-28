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
  filesOnAllHosts = builtins.all (host: let
    system = ctx.self.nixosConfigurations.${host}.config;
    home = ctx.homeConfig host;
    files = home.programs.dux-files;
    portals = system.xdg.portal.config.hyprland;
  in
    files.enable
    && !files.systemd.enable
    && !files.portal.enable
    && builtins.elem files.package home.home.packages
    && builtins.elem files.quickshell.package home.home.packages
    && builtins.elem files.package home.dbus.packages
    && builtins.elem files.package system.xdg.portal.extraPortals
    && home.xdg.mimeApps.defaultApplications."inode/directory" == ["dev.duxlabs.files.desktop"]
    && portals."org.freedesktop.impl.portal.FileChooser" == "dfiles;gtk"
    && portals."org.freedesktop.impl.portal.Settings" == "gtk"
    && portals."org.freedesktop.impl.portal.ScreenCast" == "hyprland"
    && portals."org.freedesktop.impl.portal.Screenshot" == "hyprland"
    && home.programs.yazi.enable
    && home.programs.yazi.shellWrapperName == "y")
  ctx.registry.host;
in {
  host-configuration-contracts = assert lib.assertMsg ctx.spotifyPlayerRemoved
  "spotify_player and its service/auth migration must remain removed from every host.";
  assert lib.assertMsg (aiServicesConfigured && hasCommand "ai-search" && hasCommand "searxngctl" && hasLauncher)
  "Desktop AI search must use an on-demand Open WebUI launcher, an always-on local SearXNG, and independent commands.";
  assert lib.assertMsg filesOnAllHosts
  "Dux Files must handle folders and file chooser portals on every host, with on-demand activation, GTK fallback, and terminal Yazi preserved.";
  assert lib.assertMsg guiOnAllHosts
  "The official ChatGPT desktop app with Codex must be installed on every host.";
    ctx.pkgs.runCommand "host-configuration-contracts-check" {} ''
      touch "$out"
    '';
}
