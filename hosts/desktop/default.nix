{
  pkgs,
  lib,
  config,
  ...
}: {
  imports = [
    ../common/default.nix
    ../../modules/nixos/gnome.nix
    ../../modules/nixos/hyprland.nix
    ./hardware-configuration.nix
  ];

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
    open = true; # Switch to open kernel modules for better suspend stability on RTX 3080
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.production;
  };

  # Fix for Nvidia suspend/wake issues
  boot.kernelParams = [
    "nvidia.NVreg_PreserveVideoMemoryAllocations=1"
  ];

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
      services.desktopManager.gnome.enable = lib.mkForce false;
      services.displayManager.gdm.enable = lib.mkForce false;
      programs.hyprland.enable = lib.mkForce false;
      programs.steam = {
        enable = true;
        gamescopeSession.enable = true;
      };
      programs.gamemode.enable = true;
      environment.sessionVariables = lib.mkForce {};
    };
  };

  # WireGuard VPN
  networking.networkmanager.unmanaged = ["wg-gr" "wg-us"];
  sops.defaultSopsFile = ../../secrets/secrets.yaml;
  sops.age.keyFile = "/home/stefan/.config/sops/age/keys.txt";

  sops.secrets.wireguard_gr_private_key = {};
  sops.secrets.wireguard_us_private_key = {};

  sops.templates."nixos-desktop-GR-26.conf".content = ''
    [Interface]
    # Key for nixos-desktop
    # Bouncing = 17
    # NetShield = 2
    # Moderate NAT = off
    # NAT-PMP (Port Forwarding) = on
    # VPN Accelerator = on
    PrivateKey = ${config.sops.placeholder.wireguard_gr_private_key}
    Address = 10.2.0.2/32
    DNS = 10.2.0.1

    [Peer]
    # GR#26
    PublicKey = BM3CQJ3Vo8L7aOeeyqADlN2tGcn2VPxZ+gnlKk5gLlg=
    AllowedIPs = 0.0.0.0/0, ::/0
    Endpoint = 45.92.33.162:51820

    PersistentKeepalive = 25
  '';

  sops.templates."nixos-desktop-US-FREE-33.conf".content = ''
    [Interface]
    # Key for nixos-desktop
    # Bouncing = 3
    # NetShield = 2
    # Moderate NAT = off
    # NAT-PMP (Port Forwarding) = on
    # VPN Accelerator = on
    PrivateKey = ${config.sops.placeholder.wireguard_us_private_key}
    Address = 10.2.0.2/32
    DNS = 10.2.0.1

    [Peer]
    # US-FREE#33
    PublicKey = SOXFyakZ9HI9TeiMRyMoy3PXYEzJJ/IDJcMvxZ3uWSE=
    AllowedIPs = 0.0.0.0/0, ::/0
    Endpoint = 149.102.254.90:51820

    PersistentKeepalive = 25
  '';

  networking.wg-quick.interfaces = {
    wg-gr = {
      autostart = false;
      configFile = config.sops.templates."nixos-desktop-GR-26.conf".path;
    };
    wg-us = {
      autostart = false;
      configFile = config.sops.templates."nixos-desktop-US-FREE-33.conf".path;
    };
  };
}
