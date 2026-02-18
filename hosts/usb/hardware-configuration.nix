{
  pkgs,
  lib,
  modulesPath,
  ...
}: {
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  # Enable LUKS support
  boot.initrd.luks.devices."root" = {
    device = "/dev/disk/by-partlabel/NIXOS_USB_CRYPT";
    preLVM = true;
  };

  # File Systems
  fileSystems."/" = {
    device = "/dev/mapper/root";
    fsType = "ext4";
    options = ["noatime" "nodiratime"];
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-label/NIXOS_BOOT";
    fsType = "vfat";
  };

  # Generic hardware support for portability
  hardware.enableAllFirmware = true;
  boot.initrd.availableKernelModules = ["xhci_pci" "ehci_pci" "ahci" "usb_storage" "sd_mod" "usbhid" "nvme" "uas" "virtio_pci" "virtio_blk"];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
