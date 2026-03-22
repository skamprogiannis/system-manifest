{
  pkgs,
  lib,
  config,
  ...
}: {
  imports = [
    ../common/default.nix
    ../../modules/desktop-enviroments/hyprland.nix
    ./hardware-configuration.nix
  ];

  # DMS greeter (greetd + QuickShell) replaces GDM
  services.displayManager.gdm.enable = false;
  programs.dank-material-shell.greeter = {
    enable = true;
    compositor.name = "hyprland";
    configHome = "/home/stefan";
  };
  services.greetd.settings.default_session.user = "greeter";

  # AccountsService user config — required for the greeter avatar.
  environment.etc."AccountsService/users/stefan".text = ''
    [User]
    Icon=/var/lib/AccountsService/icons/stefan
    SystemAccount=false
  '';

  # Keep the avatar file declarative and aligned with the AccountsService Icon path.
  system.activationScripts.accountsServiceAvatar = lib.stringAfter ["users"] ''
    install -dm0755 /var/lib/AccountsService/users /var/lib/AccountsService/icons

    cat > /var/lib/AccountsService/users/stefan <<'EOF'
    [User]
    Icon=/var/lib/AccountsService/icons/stefan
    SystemAccount=false
    EOF
    chmod 0644 /var/lib/AccountsService/users/stefan
    chown root:root /var/lib/AccountsService/users/stefan

    install -Dm0644 ${./assets/stefan-avatar.webp} /var/lib/AccountsService/icons/stefan
    chmod 0644 /var/lib/AccountsService/icons/stefan
    chown root:root /var/lib/AccountsService/icons/stefan
  '';

  # System-wide cursor theme (needed for greeter and other non-HM contexts)
  environment.variables = {
    XCURSOR_THEME = "Adwaita";
    XCURSOR_SIZE = "24";
  };

  # DMS greeter shells out to bash+dbus-send for user profile icons
  systemd.services.greetd.path = with pkgs; [ bash dbus systemd ];
  # Ensure greeter DBus queries and Qt image loaders resolve correctly.
  systemd.services.greetd.environment = {
    DBUS_SYSTEM_BUS_ADDRESS = "unix:path=/run/dbus/system_bus_socket";
    QT_PLUGIN_PATH = lib.concatStringsSep ":" [
      "${pkgs.qt6.qtbase}/lib/qt-6/plugins"
      "${pkgs.qt6.qtimageformats}/lib/qt-6/plugins"
    ];
  };

  networking.hostName = "desktop";

  # Bootloader
  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    device = "nodev";
    gfxmodeEfi = "1920x1080";
    configurationLimit = 20;
    theme = pkgs.stdenv.mkDerivation {
      pname = "hollow-knight-grub-theme";
      version = "1.0";
      src = pkgs.fetchFromGitHub {
        owner = "sergoncano";
        repo = "hollow-knight-grub-theme";
        rev = "9515f805f72dc214e3da59967f0b678d9910adf1";
        sha256 = "sha256-0hn3MFC+OtfwtA//pwjnWz7Oz0Cos3YzbgUlxKszhyA=";
      };
      installPhase = ''
        mkdir -p $out
        cp -r hollow-grub/* $out
        # Center the keybinds description and move it below options
        sed -i '/#Keybinds/,/}/ s/left = 10%/left = 0\n\twidth = 100%/' $out/theme.txt
        sed -i '/#Keybinds/,/}/ s/top = 82%/top = 85%/' $out/theme.txt

        # Center the logo (Nudged further left to fix bias)
        sed -i '/#Title/,/}/ s/left = 20%/left = 2%/' $out/theme.txt

        # Center the boot menu (Reverted to the 'mostly centered' 25%)
        sed -i '/#Boot menu/,/}/ s/left = 35%/left = 25%/' $out/theme.txt
      '';
    };
  };
  boot.loader.systemd-boot.enable = false;
  boot.loader.efi.canTouchEfiVariables = true;

  # Disk Encryption (Additional drives)
  boot.initrd.luks.devices."luks-a96ee21e-bc18-42ab-864c-d3ec22f4247a".device = "/dev/disk/by-uuid/a96ee21e-bc18-42ab-864c-d3ec22f4247a";
  boot.initrd.luks.devices."luks-a2df8182-4853-442b-ba7c-6ca18af8696a".device = "/dev/disk/by-uuid/a2df8182-4853-442b-ba7c-6ca18af8696a";

  # File Systems
  fileSystems."/home/stefan/games" = {
    device = "/dev/disk/by-uuid/af2d7832-b398-49d2-ab40-61aa312dbf83";
    fsType = "ext4";
  };

  # Ensure user ownership of the Games folder
  systemd.tmpfiles.rules = [
    "d /home/stefan/games 0755 stefan users - -"
  ];

  # Load the NVIDIA driver
  services.xserver.videoDrivers = ["nvidia"];

  hardware.nvidia = {
    modesetting.enable = true;
    powerManagement.enable = true; # Fixes suspend/resume issues
    powerManagement.finegrained = false;
    open = false; # Switch to open kernel modules for better suspend stability on RTX 3080
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.production;
  };

  # Suppress kernel messages during boot (greeter handles the display)
  boot.consoleLogLevel = 0;

  # Fix for Nvidia suspend/wake issues
  boot.kernelParams = [
    "nvidia.NVreg_PreserveVideoMemoryAllocations=1"
    "mem_sleep_default=deep"
    "quiet"
    "udev.log_level=3"
  ];

  # Disable USB wakeup for mice to prevent accidental wakeups from hibernation
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="usb", ATTR{product}=="*Mouse*", ATTR{power/wakeup}="disabled"
  '';

  # Enable Steam & Gamemode
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true; # Open ports for Steam Remote Play
    dedicatedServer.openFirewall = true; # Open ports for Source Dedicated Server
  };
  programs.gamemode.enable = true;

  # Gaming Specialisation (Steam Big Picture Mode)
  specialisation = {
    gaming-box.configuration = {
      system.nixos.tags = ["gaming-box"];
      programs.hyprland.enable = lib.mkForce false;
      programs.steam = {
        enable = true;
        gamescopeSession.enable = true;
      };
      programs.gamemode.enable = true;
      environment.sessionVariables = lib.mkForce {};
    };
  };
}
