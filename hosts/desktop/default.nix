{
  pkgs,
  lib,
  config,
  inputs,
  ...
}: {
  imports = [
    ../common/default.nix
    ../../modules/desktop-enviroments/hyprland.nix
    ./hardware-configuration.nix
    ./dms-greeter.nix
  ];

  networking.hostName = "desktop";

  # Bootloader
  boot.loader.systemd-boot = {
    enable = true;
    configurationLimit = 20;
  };
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

  # Ollama (local LLMs on the RTX 3080)
  services.ollama = {
    enable = true;
    package = pkgs.ollama-cuda;
    loadModels = [
      "qwen2.5-coder:14b"
      "llama3.2-vision"
      "gemma3:4b"
    ];
  };

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
