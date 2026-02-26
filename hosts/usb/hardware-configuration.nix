{
  pkgs,
  lib,
  modulesPath,
  ...
}: {
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  # Generic hardware support for portability
  boot.initrd.availableKernelModules = ["xhci_pci" "ehci_pci" "ahci" "usb_storage" "sd_mod" "usbhid" "nvme" "uas" "virtio_pci" "virtio_blk"];
  hardware.enableAllFirmware = true;

  # Enable LUKS support
  boot.initrd.luks.devices."root" = {
    device = "/dev/disk/by-partlabel/NIXOS_USB_CRYPT";
    preLVM = true;
  };

  # File Systems
  fileSystems."/" = {
    device = "/dev/disk/by-label/NIXOS_USB_ROOT";
    fsType = "ext4";
    options = ["noatime" "nodiratime"];
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-label/NIXOS_BOOT";
    fsType = "vfat";
  };

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
