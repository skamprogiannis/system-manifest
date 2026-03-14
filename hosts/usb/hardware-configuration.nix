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
  boot.initrd.availableKernelModules = [
    "xhci_pci" "ehci_pci" "ahci" "usb_storage" "sd_mod"
    "usbhid" "nvme" "uas" "virtio_pci" "virtio_blk"
    # Required for squashfs hybrid store
    "squashfs" "overlay" "loop"
  ];
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

  # Hybrid squashfs Nix store: compressed read-only image + tmpfs overlay.
  # Reads come from the squashfs (sequential, compressed, fast on USB).
  # Writes go to tmpfs (volatile — lost on reboot, fine for lab use).
  fileSystems."/nix/.ro-store" = {
    device = "/nix-store.squashfs";
    fsType = "squashfs";
    options = [ "loop" "ro" ];
    neededForBoot = true;
  };

  fileSystems."/nix/.rw-store" = {
    device = "tmpfs";
    fsType = "tmpfs";
    options = [ "mode=0755" "size=2G" ];
    neededForBoot = true;
  };

  fileSystems."/nix/store" = {
    overlay = {
      lowerdir = [ "/nix/.ro-store" ];
      upperdir = "/nix/.rw-store/upper";
      workdir = "/nix/.rw-store/work";
    };
    neededForBoot = true;
  };

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
