{
  pkgs,
  lib,
  modulesPath,
  ...
}: {
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  # Generic hardware support for portability across lab machines
  boot.initrd.availableKernelModules = [
    "xhci_pci" "ehci_pci" "ohci_pci" "uhci_hcd"
    "ahci" "usb_storage" "sd_mod" "usbhid" "hid_generic"
    "nvme" "uas" "virtio_pci" "virtio_blk"
    "sdhci_pci" "ata_piix" "ata_generic"
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
  #
  # These mounts are set up in postMountCommands rather than fileSystems
  # because the squashfs device is a file on the root partition. NixOS's
  # initrd stage-1 doesn't prefix file-based device paths with /mnt-root,
  # so `mount -o loop /nix-store.squashfs ...` fails (file not found).
  boot.initrd.postMountCommands = ''
    mkdir -p /mnt-root/nix/.ro-store /mnt-root/nix/.rw-store
    mount -t squashfs -o loop,ro /mnt-root/nix-store.squashfs /mnt-root/nix/.ro-store
    mount -t tmpfs -o mode=0755,size=2G tmpfs /mnt-root/nix/.rw-store
    mkdir -m 0755 -p /mnt-root/nix/.rw-store/upper /mnt-root/nix/.rw-store/work
    mount -t overlay overlay \
      -o lowerdir=/mnt-root/nix/.ro-store,upperdir=/mnt-root/nix/.rw-store/upper,workdir=/mnt-root/nix/.rw-store/work \
      /mnt-root/nix/store
  '';

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
