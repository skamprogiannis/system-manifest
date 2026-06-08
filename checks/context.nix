{
  self,
  pkgs,
}: rec {
  inherit self pkgs;

  registry = import ./registry.nix;

  desktopHome = self.nixosConfigurations.desktop.config.home-manager.users.stefan.home.path;
  desktopActivation = self.nixosConfigurations.desktop.config.home-manager.users.stefan.home.activationPackage;
  desktopSkwdDmsSyncHook = self.nixosConfigurations.desktop.config.home-manager.users.stefan.xdg.configFile."skwd-wall/scripts/sync-dms-wallpaper.sh".source;
  desktopZellijDevLayoutFile = pkgs.writeText "desktop-zellij-dev-layout" self.nixosConfigurations.desktop.config.home-manager.users.stefan.xdg.configFile."zellij/layouts/dev.kdl".text;
  usbHome = self.nixosConfigurations.usb.config.home-manager.users.stefan.home.path;
  usbInitrd = self.nixosConfigurations.usb.config.system.build.initialRamdisk;
  usbRamStoreInitrd = self.nixosConfigurations.usb.config.specialisation.ram-store.configuration.system.build.initialRamdisk;
  usbRamStorePrepareScript = pkgs.writeText "usb-ram-store-prepare-script" self.nixosConfigurations.usb.config.specialisation.ram-store.configuration.boot.initrd.systemd.services.initrd-usb-ram-store-prepare.script;
  usbHostAutoStoreInitrd = self.nixosConfigurations.usb.config.specialisation.host-auto-store.configuration.system.build.initialRamdisk;
  usbHostAutoStorePrepareScript = pkgs.writeText "usb-host-auto-store-prepare-script" self.nixosConfigurations.usb.config.specialisation.host-auto-store.configuration.boot.initrd.systemd.services.initrd-usb-host-auto-store-prepare.script;
  usbDmsServiceEnvironmentFile = builtins.toFile "usb-dms-service-environment" (
    builtins.concatStringsSep "\n"
    self.nixosConfigurations.usb.config.home-manager.users.stefan.systemd.user.services.dms.Service.Environment
  );
  codexConfigPython = pkgs.python3.withPackages (ps: [ps.tomli-w]);
  desktopNeovimInitFile = self.nixosConfigurations.desktop.config.home-manager.users.stefan.xdg.configFile."nvim/init.lua".source;
  neovimLangmapFile = builtins.toFile "neovim-langmap" self.nixosConfigurations.desktop.config.home-manager.users.stefan.programs.nixvim.opts.langmap;
  desktopHyprlandBindsFile = builtins.toFile "desktop-hyprland-binds" (
    builtins.concatStringsSep "\n"
    self.nixosConfigurations.desktop.config.home-manager.users.stefan.wayland.windowManager.hyprland.settings.bind
  );
  shellcheckScripts = [
    "${desktopHome}/bin/codex-state-sync"
    "${desktopHome}/bin/gsr-record"
    "${desktopHome}/bin/hypr-nav"
    "${desktopHome}/bin/hypr-quit-active"
    "${desktopHome}/bin/screenshot-path-copy"
    "${desktopHome}/bin/skwd-we-capture-still"
    "${desktopHome}/bin/spotify_player"
    "${desktopHome}/bin/transmission-port-sync"
    "${desktopHome}/bin/update-usb"
    "${desktopHome}/bin/zellij-sessionizer"
    "${desktopSkwdDmsSyncHook}"
    "${usbHome}/bin/spotify_player"
    "${usbHome}/bin/setup-persistent-usb"
  ];
}
