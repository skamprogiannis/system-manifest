{
  self,
  pkgs,
}: rec {
  inherit self pkgs;

  registry = import ./registry.nix;

  desktopHome = self.nixosConfigurations.desktop.config.home-manager.users.stefan.home.path;
  desktopActivation = self.nixosConfigurations.desktop.config.home-manager.users.stefan.home.activationPackage;
  desktopSkwdDmsSyncHook = self.nixosConfigurations.desktop.config.home-manager.users.stefan.xdg.configFile."skwd-wall/scripts/sync-dms-wallpaper.sh".source;
  desktopSkwdDmsScheduleHook = self.nixosConfigurations.desktop.config.home-manager.users.stefan.xdg.configFile."skwd-wall/scripts/schedule-dms-wallpaper-sync.sh".source;
  desktopSkwdPrepareStateActivationFile = pkgs.writeText "desktop-skwd-prepare-state-activation" self.nixosConfigurations.desktop.config.home-manager.users.stefan.home.activation.ensureWritableSkwdConfig.data;
  desktopDmsSettingsFile = pkgs.writeText "desktop-dms-settings.json" (builtins.toJSON self.nixosConfigurations.desktop.config.home-manager.users.stefan.programs.dank-material-shell.settings);
  desktopGtk4ExtraCssFile = pkgs.writeText "desktop-gtk4-extra.css" self.nixosConfigurations.desktop.config.home-manager.users.stefan.gtk.gtk4.extraCss;
  desktopSpicetifyAdditionalCssFile = pkgs.writeText "desktop-spicetify-additional.css" self.nixosConfigurations.desktop.config.home-manager.users.stefan.programs.spicetify.theme.additionalCss;
  desktopSpicetifyExtraCommandsFile = pkgs.writeText "desktop-spicetify-extra-commands" self.nixosConfigurations.desktop.config.home-manager.users.stefan.programs.spicetify.extraCommands;
  desktopSpicetifyInjectThemeJsFile = pkgs.writeText "desktop-spicetify-inject-theme-js" (builtins.toJSON self.nixosConfigurations.desktop.config.home-manager.users.stefan.programs.spicetify.theme.injectThemeJs);
  desktopTmpfilesRulesFile = pkgs.writeText "desktop-tmpfiles-rules" (builtins.concatStringsSep "\n" self.nixosConfigurations.desktop.config.systemd.tmpfiles.rules);
  desktopZellijDevLayoutFile = pkgs.writeText "desktop-zellij-dev-layout" self.nixosConfigurations.desktop.config.home-manager.users.stefan.xdg.configFile."zellij/layouts/dev.kdl".text;
  updateUsbSourceDir = ../modules/home/scripts/usb/update-usb;
  usbHome = self.nixosConfigurations.usb.config.home-manager.users.stefan.home.path;
  usbActivation = self.nixosConfigurations.usb.config.home-manager.users.stefan.home.activationPackage;
  usbInitrd = self.nixosConfigurations.usb.config.system.build.initialRamdisk;
  usbRamStoreInitrd = self.nixosConfigurations.usb.config.specialisation.ram-store.configuration.system.build.initialRamdisk;
  usbRamStorePrepareScript = pkgs.writeText "usb-ram-store-prepare-script" self.nixosConfigurations.usb.config.specialisation.ram-store.configuration.boot.initrd.systemd.services.initrd-usb-ram-store-prepare.script;
  usbHostAutoStoreInitrd = self.nixosConfigurations.usb.config.specialisation.host-auto-store.configuration.system.build.initialRamdisk;
  usbHostAutoStorePrepareScript = pkgs.writeText "usb-host-auto-store-prepare-script" self.nixosConfigurations.usb.config.specialisation.host-auto-store.configuration.boot.initrd.systemd.services.initrd-usb-host-auto-store-prepare.script;
  usbHostScratchService = self.nixosConfigurations.usb.config.systemd.services.usb-host-scratch;
  usbHostScratchServiceDescriptionFile = builtins.toFile "usb-host-scratch-service-description" usbHostScratchService.description;
  usbHostScratchStopScript = usbHostScratchService.serviceConfig.ExecStop;
  usbHostScratchShutdownCleanupScript = self.nixosConfigurations.usb.config.systemd.shutdownRamfs.contents."/lib/systemd/system-shutdown/usb-host-scratch-cleanup".source;
  usbShutdownRamfsStorePathsFile = pkgs.writeText "usb-shutdown-ramfs-store-paths" (
    builtins.concatStringsSep "\n" (
      map (entry: entry.source) self.nixosConfigurations.usb.config.systemd.shutdownRamfs.storePaths
    )
  );
  usbDmsServiceEnvironmentFile = builtins.toFile "usb-dms-service-environment" (
    builtins.concatStringsSep "\n"
    self.nixosConfigurations.usb.config.home-manager.users.stefan.systemd.user.services.dms.Service.Environment
  );
  codexConfigPython = pkgs.python3.withPackages (ps: [ps.tomli-w]);
  desktopNeovimInitFile = self.nixosConfigurations.desktop.config.home-manager.users.stefan.xdg.configFile."nvim/init.lua".source;
  neovimLangmapFile = builtins.toFile "neovim-langmap" self.nixosConfigurations.desktop.config.home-manager.users.stefan.programs.nixvim.opts.langmap;
  desktopGreeterPackage = self.nixosConfigurations.desktop.config.programs.dank-material-shell.greeter.package;
  desktopAccountsServiceAvatarScript = pkgs.writeText "desktop-accounts-service-avatar-script" self.nixosConfigurations.desktop.config.system.activationScripts.accountsServiceAvatar.text;
  desktopHyprlandPackage = self.nixosConfigurations.desktop.config.home-manager.users.stefan.wayland.windowManager.hyprland.finalPackage;
  desktopHyprlandLuaFile = pkgs.writeText "desktop-hyprland.lua" self.nixosConfigurations.desktop.config.home-manager.users.stefan.xdg.configFile."hypr/hyprland.lua".text;
  laptopHyprlandLuaFile = pkgs.writeText "laptop-hyprland.lua" self.nixosConfigurations.laptop.config.home-manager.users.stefan.xdg.configFile."hypr/hyprland.lua".text;
  usbHyprlandLuaFile = pkgs.writeText "usb-hyprland.lua" self.nixosConfigurations.usb.config.home-manager.users.stefan.xdg.configFile."hypr/hyprland.lua".text;
  desktopGhosttySettingsFile = pkgs.writeText "desktop-ghostty-settings.json" (builtins.toJSON self.nixosConfigurations.desktop.config.home-manager.users.stefan.programs.ghostty.settings);
  desktopDmsOutputsFile = pkgs.writeText "desktop-dms-outputs.lua" self.nixosConfigurations.desktop.config.home-manager.users.stefan.xdg.configFile."hypr/dms/outputs.lua".text;
  desktopDmsLegacyProfileFile = pkgs.writeText "desktop-dms-profile.conf" self.nixosConfigurations.desktop.config.home-manager.users.stefan.xdg.configFile."hypr/dms/profiles/desktop.conf".text;
  laptopDmsOutputsFile = pkgs.writeText "laptop-dms-outputs.lua" self.nixosConfigurations.laptop.config.home-manager.users.stefan.xdg.configFile."hypr/dms/outputs.lua".text;
  usbDmsOutputsFile = pkgs.writeText "usb-dms-outputs.lua" self.nixosConfigurations.usb.config.home-manager.users.stefan.xdg.configFile."hypr/dms/outputs.lua".text;
  shellcheckScripts = [
    "${desktopHome}/bin/codex-state-sync"
    "${desktopHome}/bin/gsr-record"
    "${desktopHome}/bin/hypr-quit-active"
    "${desktopHome}/bin/screenshot-path-copy"
    "${desktopHome}/bin/skwd-we-capture-still"
    "${desktopHome}/bin/spotify_player"
    "${desktopHome}/bin/transmission-port-sync"
    "${desktopHome}/bin/update-usb"
    "${desktopHome}/bin/zellij-sessionizer"
    "${desktopSkwdDmsSyncHook}"
    "${updateUsbSourceDir}/args.sh"
    "${updateUsbSourceDir}/cleanup.sh"
    "${updateUsbSourceDir}/main.sh"
    "${updateUsbSourceDir}/metadata.sh"
    "${updateUsbSourceDir}/phases.sh"
    "${updateUsbSourceDir}/squashfs.sh"
    "${usbHome}/bin/usb-host-scratch"
    "${usbHome}/bin/nixos-usb-store-status"
    "${usbHostScratchStopScript}"
    "${usbHostScratchShutdownCleanupScript}"
    "${usbHome}/bin/spotify_player"
    "${usbHome}/bin/setup-persistent-usb"
  ];
}
