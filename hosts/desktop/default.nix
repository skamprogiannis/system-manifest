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
    ./dms-greeter.nix
  ];

  networking.hostName = "desktop";

  # Bootloader
  boot.loader.systemd-boot = {
    enable = true;
    configurationLimit = 20;
  };
  boot.loader.efi.canTouchEfiVariables = true;
  system.activationScripts.preferSystemdBoot = lib.stringAfter ["etc"] ''
    if [ -d /sys/firmware/efi/efivars ]; then
      efi_output="$(${pkgs.efibootmgr}/bin/efibootmgr 2>/dev/null || true)"
      systemd_entry="$(printf '%s\n' "$efi_output" \
        | ${pkgs.gnugrep}/bin/grep -E '^Boot[0-9A-Fa-f]{4}\*?[[:space:]]+Linux Boot Manager([[:space:]].*)?$' \
        | ${pkgs.coreutils}/bin/head -n 1 \
        | ${pkgs.gnused}/bin/sed -E 's/^Boot([0-9A-Fa-f]{4}).*/\1/')"
      boot_order="$(printf '%s\n' "$efi_output" \
        | ${pkgs.gnused}/bin/sed -n 's/^BootOrder: //p' \
        | ${pkgs.coreutils}/bin/head -n 1)"

      if [ -n "$systemd_entry" ] && [ -n "$boot_order" ]; then
        systemd_entry="$(printf '%s' "$systemd_entry" | ${pkgs.coreutils}/bin/tr '[:lower:]' '[:upper:]')"
        new_order="$systemd_entry"
        old_ifs="$IFS"
        IFS=,
        for entry in $boot_order; do
          entry="$(printf '%s' "$entry" | ${pkgs.coreutils}/bin/tr '[:lower:]' '[:upper:]')"
          [ "$entry" = "$systemd_entry" ] && continue
          new_order="$new_order,$entry"
        done
        IFS="$old_ifs"

        if [ "$boot_order" != "$new_order" ]; then
          ${pkgs.efibootmgr}/bin/efibootmgr -o "$new_order" >/dev/null
        fi
      fi
    fi
  '';

  # Keep the games drive on the initrd unlock path for now. Delaying it to
  # stage 2 prompted during `switch` because the existing mount gets restarted.
  boot.initrd.luks.devices."luks-a96ee21e-bc18-42ab-864c-d3ec22f4247a".device = "/dev/disk/by-uuid/a96ee21e-bc18-42ab-864c-d3ec22f4247a";
  # Swap uses stage-2 random encryption rather than an initrd unlock. Keep a
  # one-time activation migration to remove the old LUKS wrapper/signature.
  system.activationScripts.swapRandomEncryptionMigration = lib.stringAfter ["etc"] ''
    swap_part=/dev/disk/by-partuuid/2a7da6b2-de21-4c28-a2cc-704fea184f2f
    old_mapper=luks-a2df8182-4853-442b-ba7c-6ca18af8696a
    old_mapper_dev=/dev/mapper/$old_mapper

    ${pkgs.util-linux}/bin/swapoff "$old_mapper_dev" 2>/dev/null || true

    if [ -e "$old_mapper_dev" ]; then
      ${pkgs.cryptsetup}/bin/cryptsetup luksClose "$old_mapper" 2>/dev/null || true
    fi

    if ${pkgs.cryptsetup}/bin/cryptsetup isLuks "$swap_part" 2>/dev/null; then
      ${pkgs.util-linux}/bin/wipefs -a "$swap_part"
      ${pkgs.systemd}/bin/udevadm settle
    fi
  '';

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
    "nohibernate"
    "quiet"
    "systemd.show_status=false"
    "rd.systemd.show_status=false"
    "udev.log_level=3"
  ];

  i18n.inputMethod = {
    enable = true;
    type = "ibus";
  };

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
