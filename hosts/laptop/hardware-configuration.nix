{
  lib,
  modulesPath,
  ...
}: {
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  boot.initrd.availableKernelModules = [
    "xhci_pci"
    "nvme"
    "usb_storage"
    "sd_mod"
  ];

  boot.initrd.luks.devices."nixos-laptop-root".device = "/dev/disk/by-partlabel/NIXOS_LAPTOP_CRYPT";

  fileSystems."/" = {
    device = "/dev/disk/by-label/NIXOS_LAPTOP_ROOT";
    fsType = "ext4";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-label/NIXOS_LAPTOP_BOOT";
    fsType = "vfat";
    options = [
      "fmask=0022"
      "dmask=0022"
    ];
  };

  swapDevices = [];

  hardware.enableRedistributableFirmware = true;
  networking.useDHCP = lib.mkDefault true;
}
