{
  pkgs,
  lib,
  modulesPath,
  ...
}: {
  imports = [
    ../common/default.nix
    ../../modules/nixos/gnome.nix
    ../../modules/nixos/hyprland.nix
    ./hardware-configuration.nix
  ];

  networking.hostName = "nixos-usb";

  # Bootloader (Hollow GRUB style)
  boot.loader.grub = {
    enable = true;
    device = "nodev";
    efiSupport = true;
    useOSProber = false;
    # Ensure it installs to the removable media path for maximum USB compatibility
    # (EFI/BOOT/BOOTX64.EFI) so any BIOS picks it up.
    efiInstallAsRemovable = true;
  };
  boot.loader.efi.canTouchEfiVariables = false;

  # Ensure the USB doesn't try to load Nvidia drivers from the host
  services.xserver.videoDrivers = lib.mkForce ["modesetting" "fbdev"];

  # User setup
  users.users.stefan.initialPassword = "nixos";
}
