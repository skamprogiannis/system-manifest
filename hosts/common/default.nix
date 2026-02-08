# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).
{
  config,
  pkgs,
  inputs,
  lib,
  ...
}: {
  imports = [
    # hardware-configuration.nix is imported by the specific host
  ];

  # Track configuration revision
  system.configurationRevision = inputs.self.rev or inputs.self.dirtyRev or null;

  # Enable experimental features natively
  nix.settings.experimental-features = ["nix-command" "flakes"];

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

        # Center the logo (956px wide on 1920px screen -> left=482)
        sed -i '/#Title/,/}/ s/left = 20%/left = 482/' $out/theme.txt

        # Center the boot menu (540px wide on 1920px screen -> left=690)
        # 1920/2 - 540/2 = 690px
        sed -i '/#Boot menu/,/}/ s/left = 35%/left = 690/' $out/theme.txt
      '';
    };
  };
  boot.loader.systemd-boot.enable = false;
  boot.loader.efi.canTouchEfiVariables = true;
  # Use LTS kernel for better stability
  boot.kernelPackages = pkgs.linuxPackages;

  # Disk Encryption
  boot.initrd.luks.devices."luks-b09a5bbd-396d-4ce6-a15f-989ed1554773".device = "/dev/disk/by-uuid/b09a5bbd-396d-4ce6-a15f-989ed1554773";
  boot.initrd.luks.devices."luks-a2df8182-4853-442b-ba7c-6ca18af8696a".device = "/dev/disk/by-uuid/a2df8182-4853-442b-ba7c-6ca18af8696a";
  boot.initrd.luks.devices."luks-a96ee21e-bc18-42ab-864c-d3ec22f4247a".device = "/dev/disk/by-uuid/a96ee21e-bc18-42ab-864c-d3ec22f4247a";

  # File Systems
  fileSystems."/home/stefan/Games" = {
    device = "/dev/disk/by-uuid/af2d7832-b398-49d2-ab40-61aa312dbf83";
    fsType = "ext4";
  };

  # Ensure user ownership of the Games folder
  systemd.tmpfiles.rules = [
    "d /home/stefan/Games 0755 stefan users - -"
  ];

  # Networking
  # HostName is defined in host specific config
  networking.networkmanager.enable = true;

  # Time & Locales
  time.timeZone = "Europe/Athens";
  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "el_GR.UTF-8";
    LC_IDENTIFICATION = "el_GR.UTF-8";
    LC_MEASUREMENT = "el_GR.UTF-8";
    LC_MONETARY = "el_GR.UTF-8";
    LC_NAME = "el_GR.UTF-8";
    LC_PAPER = "el_GR.UTF-8";
    LC_TELEPHONE = "el_GR.UTF-8";
    LC_NUMERIC = "en_GB.UTF-8";
    LC_TIME = "en_GB.UTF-8";
  };

  # Enable OpenGL
  hardware.graphics.enable = true;

  # Enable the X11 windowing system
  services.xserver.enable = true;

  # Enable nix-ld for Opencode/dynamic binaries
  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [
    stdenv.cc.cc.lib
    zlib
    openssl
  ];

  # Allow the user to rebuild the system without a password
  security.sudo.extraRules = [
    {
      users = ["stefan"];
      commands = [
        {
          command = "/run/current-system/sw/bin/nixos-rebuild";
          options = ["NOPASSWD"];
        }
      ];
    }
  ];

  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "us,gr";
    variant = "altgr-intl,";
    options = "grp:win_space_toggle";
  };

  # Enable CUPS to print documents
  services.printing.enable = true;

  # Enable sound with pipewire
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    # If you want to use JACK applications, uncomment this
    #jack.enable = true;
  };

  # Define a user account. Don't forget to set a password with ‘passwd’
  users.users.stefan = {
    isNormalUser = true;
    description = "Stefan";
    extraGroups = ["networkmanager" "wheel"];
    packages = with pkgs; [
      #  thunderbird
    ];
  };

  # Install firefox.
  programs.firefox.enable = true;

  # Enable Steam & Gamemode globally
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true; # Open ports for Steam Remote Play
    dedicatedServer.openFirewall = true; # Open ports for Source Dedicated Server
  };
  programs.gamemode.enable = true;

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;
  nixpkgs.config.permittedInsecurePackages = [
    "libsoup-2.74.3"
  ];

  # Required for Home Manager XDG portals
  environment.pathsToLink = ["/share/applications" "/share/xdg-desktop-portal"];

  # List packages installed in system profile.
  environment.systemPackages = with pkgs; [
    wget
    git
  ];

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "25.11"; # Did you read the comment?
}
