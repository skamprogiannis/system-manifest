{
  self,
  pkgs,
}: rec {
  inherit self pkgs;

  registry = import ./registry.nix;
  serviceExec = service:
    builtins.head (pkgs.lib.splitString " " service.serviceConfig.ExecStart);

  homeConfig = host: self.nixosConfigurations.${host}.config.home-manager.users.stefan;
  namedPackage = label: name: packages: let
    matches = builtins.filter (package: pkgs.lib.getName package == name) packages;
    count = builtins.length matches;
  in
    if count == 1
    then builtins.head matches
    else throw "${label}: expected one package named ${name}, found ${toString count}";
  homePackage = host: name: namedPackage "${host} home.packages" name (homeConfig host).home.packages;
  scriptArtifacts = host: commands:
    pkgs.linkFarm "${host}-check-script-artifacts" (pkgs.lib.mapAttrsToList (command: packageName: {
        name = "bin/${command}";
        path = "${homePackage host packageName}/bin/${command}";
      })
      commands);
  desktopScriptArtifacts = scriptArtifacts "desktop" {
    codex = "codex-cli-wrapped";
    codex-state-sync = "codex-state-sync";
    gsr-record = "gsr-record";
    torrent = "torrent";
    transmission-port-sync = "transmission-port-sync";
    update-usb = "update-usb";
    zellij-sessionizer = "zellij-sessionizer";
  };
  desktopHomeFiles = self.nixosConfigurations.desktop.config.home-manager.users.stefan.home.file;
  desktopNvidiaDriverVersion = self.nixosConfigurations.desktop.config.hardware.nvidia.package.version;
  desktopGpuScreenRecorderPackage = self.nixosConfigurations.desktop.config.programs.gpu-screen-recorder.package;
  desktopGpuScreenRecorderGtkPackage = homePackage "desktop" "gpu-screen-recorder-gtk";
  desktopBravePackage = (homeConfig "desktop").programs.brave.finalPackage;
  desktopNeovimPackage = (homeConfig "desktop").programs.nixvim.build.package;
  desktopNeovimToolPackages = map (homePackage "desktop") ["clang-tools" "go" "prettier" "stylelint"];
  desktopPinchtabPackage = homePackage "desktop" "pinchtab";
  codexConfigActivationFile = host:
    pkgs.writeText "${host}-codex-config-activation" (homeConfig host).home.activation.ensureWritableCodexConfig.data;
  desktopCodexConfigActivationFile = codexConfigActivationFile "desktop";
  desktopCodexSkillsRoot = pkgs.linkFarm "desktop-codex-skills" (
    map
    (name: {
      name = pkgs.lib.removePrefix ".agents/skills/" name;
      path = desktopHomeFiles.${name}.source;
    })
    (builtins.filter
      (name: pkgs.lib.hasPrefix ".agents/skills/" name)
      (builtins.attrNames desktopHomeFiles))
  );
  desktopPinchtabConfigActivationFile = pkgs.writeText "desktop-pinchtab-config-activation" self.nixosConfigurations.desktop.config.home-manager.users.stefan.home.activation.ensurePinchTabConfig.data;
  desktopBannerlordEnabled = self.nixosConfigurations.desktop.config.home-manager.users.stefan.system_manifest.bannerlord.enable;
  desktopSkwdWalldService = self.nixosConfigurations.desktop.config.systemd.user.services.skwd-walld;
  desktopSkwdWalldExec = desktopSkwdWalldService.serviceConfig.ExecStart;
  desktopDmsPackage = self.nixosConfigurations.desktop.config.home-manager.users.stefan.programs.dank-material-shell.package;
  desktopDmsSettingsFile = pkgs.writeText "desktop-dms-settings.json" (builtins.toJSON self.nixosConfigurations.desktop.config.home-manager.users.stefan.programs.dank-material-shell.settings);
  desktopGtk4ExtraCssFile = pkgs.writeText "desktop-gtk4-extra.css" self.nixosConfigurations.desktop.config.home-manager.users.stefan.gtk.gtk4.extraCss;
  desktopSpicetifyAdditionalCssFile = pkgs.writeText "desktop-spicetify-additional.css" self.nixosConfigurations.desktop.config.home-manager.users.stefan.programs.spicetify.theme.additionalCss;
  desktopSpicetifyExtraCommandsFile = pkgs.writeText "desktop-spicetify-extra-commands" self.nixosConfigurations.desktop.config.home-manager.users.stefan.programs.spicetify.extraCommands;
  desktopSpicetifyInjectThemeJsFile = pkgs.writeText "desktop-spicetify-inject-theme-js" (builtins.toJSON self.nixosConfigurations.desktop.config.home-manager.users.stefan.programs.spicetify.theme.injectThemeJs);
  desktopNixpkgsSpotify = self.nixosConfigurations.desktop.pkgs.spotify;
  desktopSpotifyPackage = self.nixosConfigurations.desktop.config.home-manager.users.stefan.programs.spicetify.spotifyPackage;
  desktopSpicedSpotify = self.nixosConfigurations.desktop.config.home-manager.users.stefan.programs.spicetify.spicedSpotify;
  spotifyPlayerRemoved = builtins.all (host: let
    home = self.nixosConfigurations.${host}.config.home-manager.users.stefan;
  in
    !home.programs.spotify-player.enable
    && !(home.systemd.user.services ? spotify-player)
    && !(home.home.activation ? spotifyUsbAuthMigration)) ["desktop" "usb" "laptop"];
  desktopTmpfilesRulesFile = pkgs.writeText "desktop-tmpfiles-rules" (builtins.concatStringsSep "\n" self.nixosConfigurations.desktop.config.systemd.tmpfiles.rules);
  desktopZellijDevLayoutFile = pkgs.writeText "desktop-zellij-dev-layout" self.nixosConfigurations.desktop.config.home-manager.users.stefan.xdg.configFile."zellij/layouts/dev.kdl".text;
  desktopZellijLegacyArgsScrubActivationFile = pkgs.writeText "desktop-zellij-legacy-args-scrub-activation" self.nixosConfigurations.desktop.config.home-manager.users.stefan.home.activation.scrubLegacyZellijContext7Args.data;
  desktopZellijPostCommandDiscoveryHook = self.nixosConfigurations.desktop.config.home-manager.users.stefan.programs.zellij.settings.post_command_discovery_hook;
  updateUsbSourceDir = ../modules/home/scripts/usb/update-usb;
  usbScriptArtifacts = scriptArtifacts "usb" {
    nixos-usb-store-status = "nixos-usb-store-status";
    setup-persistent-usb = "setup-persistent-usb";
    steam-host-scratch = "steam-host-scratch";
    usb-host-scratch = "usb-host-scratch";
  };
  usbSystem = self.nixosConfigurations.usb.config.system.build.toplevel;
  usbSteamEnabled = self.nixosConfigurations.usb.config.programs.steam.enable;
  usbSteamLauncher = "${self.nixosConfigurations.usb.config.programs.steam.package}/bin/steam";
  usbHostAutoSteamLauncher = "${self.nixosConfigurations.usb.config.specialisation.host-auto-store.configuration.programs.steam.package}/bin/steam";
  usbSteamHostScratchPrepareScript = self.nixosConfigurations.usb.config.systemManifest.usb.steamHostScratch.prepareScript;
  usbGamemodeEnabled = self.nixosConfigurations.usb.config.programs.gamemode.enable;
  usbGraphics32Enabled = self.nixosConfigurations.usb.config.hardware.graphics.enable32Bit;
  usbGraphics32Package = self.nixosConfigurations.usb.config.hardware.graphics.package32;
  usbMesa32Package = self.nixosConfigurations.usb.pkgs.pkgsi686Linux.mesa;
  desktopHostFingerprintService = self.nixosConfigurations.desktop.config.systemd.services.system-manifest-host-fingerprint;
  laptopHostFingerprintService = self.nixosConfigurations.laptop.config.systemd.services.system-manifest-host-fingerprint;
  usbHostFingerprintService = self.nixosConfigurations.usb.config.systemd.services.system-manifest-host-fingerprint;
  desktopHostFingerprintExec = serviceExec desktopHostFingerprintService;
  laptopHostFingerprintExec = serviceExec laptopHostFingerprintService;
  usbHostFingerprintExec = serviceExec usbHostFingerprintService;
  usbHostFingerprintBeforeFile = builtins.toFile "usb-host-fingerprint-before" (
    builtins.concatStringsSep "\n" usbHostFingerprintService.before
  );
  usbDmsPackage = self.nixosConfigurations.usb.config.home-manager.users.stefan.programs.dank-material-shell.package;
  usbInitrd = self.nixosConfigurations.usb.config.system.build.initialRamdisk;
  usbRamStoreInitrd = self.nixosConfigurations.usb.config.specialisation.ram-store.configuration.system.build.initialRamdisk;
  usbRamStorePrepareScript = pkgs.writeText "usb-ram-store-prepare-script" self.nixosConfigurations.usb.config.specialisation.ram-store.configuration.boot.initrd.systemd.services.initrd-usb-ram-store-prepare.script;
  usbHostAutoStoreInitrd = self.nixosConfigurations.usb.config.specialisation.host-auto-store.configuration.system.build.initialRamdisk;
  usbHostAutoStorePrepareScript = pkgs.writeText "usb-host-auto-store-prepare-script" self.nixosConfigurations.usb.config.specialisation.host-auto-store.configuration.boot.initrd.systemd.services.initrd-usb-host-auto-store-prepare.script;
  usbHostScratchService = self.nixosConfigurations.usb.config.systemd.services.usb-host-scratch;
  usbHostScratchServiceDescriptionFile = builtins.toFile "usb-host-scratch-service-description" usbHostScratchService.description;
  usbHostScratchServiceBeforeFile = builtins.toFile "usb-host-scratch-service-before" (
    builtins.concatStringsSep "\n" usbHostScratchService.before
  );
  usbHostScratchServiceTimeoutStopSecFile = builtins.toFile "usb-host-scratch-service-timeout-stop-sec" usbHostScratchService.serviceConfig.TimeoutStopSec;
  usbHostScratchMountUnit = self.nixosConfigurations.usb.config.systemd.units."nix-.host-scratch.mount" or {};
  usbHostScratchMountDropinFile = pkgs.writeText "usb-host-scratch-mount-dropin" ''
    overrideStrategy=${usbHostScratchMountUnit.overrideStrategy or ""}
    ${usbHostScratchMountUnit.text or ""}
  '';
  usbHostStoreMountUnit = self.nixosConfigurations.usb.config.systemd.units."nix-.host-store.mount" or {};
  usbHostStoreMountDropinFile = pkgs.writeText "usb-host-store-mount-dropin" ''
    overrideStrategy=${usbHostStoreMountUnit.overrideStrategy or ""}
    ${usbHostStoreMountUnit.text or ""}
  '';
  usbHostScratchStartScript = usbHostScratchService.serviceConfig.ExecStart;
  usbHostScratchStopScript = usbHostScratchService.serviceConfig.ExecStop;
  usbHostScratchCheckpointExec = self.nixosConfigurations.usb.config.systemd.services.usb-host-scratch-checkpoint.serviceConfig.ExecStart;
  usbHostScratchSyncScript = builtins.head (pkgs.lib.splitString " " usbHostScratchCheckpointExec);
  usbTmpfilesRulesFile = pkgs.writeText "usb-tmpfiles-rules" (
    builtins.concatStringsSep "\n" self.nixosConfigurations.usb.config.systemd.tmpfiles.rules
  );
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
  desktopGreeterPackage = self.nixosConfigurations.desktop.config.programs.dms-greeter.package;
  desktopGreeterHyprlandLuaFile = pkgs.writeText "desktop-greeter-hyprland.lua" ''
    ${self.nixosConfigurations.desktop.config.programs.dms-greeter.compositor.customConfig}
    hl.on("hyprland.start", function()
      hl.exec_cmd("true")
    end)
  '';
  desktopAccountsServiceAvatarScript = pkgs.writeText "desktop-accounts-service-avatar-script" self.nixosConfigurations.desktop.config.system.activationScripts.accountsServiceAvatar.text;
  desktopMimeDefaultApplicationsFile = pkgs.writeText "desktop-mime-default-applications.json" (builtins.toJSON self.nixosConfigurations.desktop.config.home-manager.users.stefan.xdg.mimeApps.defaultApplications);
  desktopHyprlandPackage = self.nixosConfigurations.desktop.config.home-manager.users.stefan.wayland.windowManager.hyprland.finalPackage;
  desktopHyprlandLuaFile = pkgs.writeText "desktop-hyprland.lua" self.nixosConfigurations.desktop.config.home-manager.users.stefan.xdg.configFile."hypr/hyprland.lua".text;
  desktopBraveExtensionsFile = pkgs.writeText "desktop-brave-extensions.json" (
    builtins.toJSON self.nixosConfigurations.desktop.config.home-manager.users.stefan.programs.brave.extensions
  );
  laptopHyprlandLuaFile = pkgs.writeText "laptop-hyprland.lua" self.nixosConfigurations.laptop.config.home-manager.users.stefan.xdg.configFile."hypr/hyprland.lua".text;
  usbHyprlandLuaFile = pkgs.writeText "usb-hyprland.lua" self.nixosConfigurations.usb.config.home-manager.users.stefan.xdg.configFile."hypr/hyprland.lua".text;
  desktopGhosttySettingsFile = pkgs.writeText "desktop-ghostty-settings.json" (builtins.toJSON self.nixosConfigurations.desktop.config.home-manager.users.stefan.programs.ghostty.settings);
  desktopDmsOutputsFile = pkgs.writeText "desktop-dms-outputs.lua" self.nixosConfigurations.desktop.config.home-manager.users.stefan.xdg.configFile."hypr/dms/outputs.lua".text;
  desktopDmsLegacyProfileFile = pkgs.writeText "desktop-dms-profile.conf" self.nixosConfigurations.desktop.config.home-manager.users.stefan.xdg.configFile."hypr/dms/profiles/desktop.conf".text;
  laptopDmsOutputsFile = pkgs.writeText "laptop-dms-outputs.lua" self.nixosConfigurations.laptop.config.home-manager.users.stefan.xdg.configFile."hypr/dms/outputs.lua".text;
  usbDmsOutputsFile = pkgs.writeText "usb-dms-outputs.lua" self.nixosConfigurations.usb.config.home-manager.users.stefan.xdg.configFile."hypr/dms/outputs.lua".text;
  shellcheckScripts =
    pkgs.lib.optionals desktopBannerlordEnabled [
      "${homePackage "desktop" "bannerlord-codex"}/bin/bannerlord-codex"
    ]
    ++ [
      "${homePackage "desktop" "codex-state-sync"}/bin/codex-state-sync"
      "${homePackage "desktop" "gsr-record"}/bin/gsr-record"
      "${homePackage "desktop" "hypr-quit-active"}/bin/hypr-quit-active"
      "${homePackage "desktop" "screenshot-path-copy"}/bin/screenshot-path-copy"
      "${homePackage "desktop" "torrent"}/bin/torrent"
      "${homePackage "desktop" "transmission-port-sync"}/bin/transmission-port-sync"
      "${homePackage "desktop" "update-usb"}/bin/update-usb"
      "${homePackage "desktop" "zellij-sessionizer"}/bin/zellij-sessionizer"
      "${desktopZellijLegacyArgsScrubActivationFile}"
      "${desktopZellijPostCommandDiscoveryHook}"
      "${updateUsbSourceDir}/args.sh"
      "${updateUsbSourceDir}/cleanup.sh"
      "${updateUsbSourceDir}/main.sh"
      "${updateUsbSourceDir}/metadata.sh"
      "${updateUsbSourceDir}/phases.sh"
      "${updateUsbSourceDir}/squashfs.sh"
      "${updateUsbSourceDir}/staging.sh"
      "${updateUsbSourceDir}/telemetry.sh"
      "${updateUsbSourceDir}/transaction.sh"
      "${./usb-update-progress.sh}"
      "${./usb-update-unit.sh}"
      "${./usb-update-integration.sh}"
      "${./usb-host-scratch-shutdown.sh}"
      "${homePackage "usb" "usb-host-scratch"}/bin/usb-host-scratch"
      "${homePackage "usb" "steam-host-scratch"}/bin/steam-host-scratch"
      "${usbSteamHostScratchPrepareScript}"
      "${homePackage "usb" "nixos-usb-store-status"}/bin/nixos-usb-store-status"
      "${usbHostScratchStartScript}"
      "${usbHostScratchStopScript}"
      "${usbHostScratchSyncScript}"
      "${usbHostScratchShutdownCleanupScript}"
      "${homePackage "usb" "setup-persistent-usb"}/bin/setup-persistent-usb"
    ];
}
