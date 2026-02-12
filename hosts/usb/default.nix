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

  # Enable LUKS support
  boot.initrd.luks.devices."root" = {
    device = "/dev/disk/by-partlabel/NIXOS_USB_CRYPT";
    preLVM = true;
  };

  # File Systems
  fileSystems."/" = {
    device = "/dev/mapper/root";
    fsType = "ext4";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-label/NIXOS_BOOT";
    fsType = "vfat";
  };

  # Generic hardware support for portability
  hardware.enableAllFirmware = true;
  boot.initrd.availableKernelModules = ["xhci_pci" "ehci_pci" "ahci" "usb_storage" "sd_mod" "usbhid"];

  # Performance Tweaks for USB (reduce write wear)
  fileSystems."/".options = ["noatime" "nodiratime"];

  # User setup
  users.users.stefan.initialPassword = "nixos";
}
