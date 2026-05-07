{
  pkgs,
  lib,
  modulesPath,
  ...
}: let
  usb = import ../../modules/shared/usb-constants.nix;
in {
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  # Generic hardware support for portability across lab machines
  boot.initrd.availableKernelModules = [
    "xhci_pci"
    "ehci_pci"
    "ohci_pci"
    "uhci_hcd"
    "ahci"
    "usb_storage"
    "sd_mod"
    "usbhid"
    "hid_generic"
    "nvme"
    "uas"
    "virtio_pci"
    "virtio_blk"
    "sdhci_pci"
    "ata_piix"
    "ata_generic"
  ];
  # Force-load squashfs/loop/overlay so they are active before
  # postMountCommands tries to mount the squashfs store image.
  # availableKernelModules only bundles them in the initrd — it does
  # not guarantee they are loaded when postMountCommands executes.
  boot.initrd.kernelModules = ["loop" "squashfs" "overlay"];
  hardware.enableAllFirmware = true;

  # Enable LUKS support
  boot.initrd.luks.devices."root" = {
    device = usb.rootPartByLabel;
    preLVM = true;
  };

  # File Systems
  fileSystems."/" = {
    device = usb.rootFsByLabel;
    fsType = "ext4";
    options = ["noatime" "nodiratime"];
  };

  fileSystems."/boot" = {
    device = usb.bootByLabel;
    fsType = "vfat";
  };

  # Hybrid squashfs Nix store: compressed read-only image + tmpfs overlay.
  # Reads come from the squashfs (sequential, compressed, fast on USB).
  # Writes go to tmpfs (volatile — lost on reboot, fine for lab use).
  #
  # Newer systemd initrd forbids postMountCommands, so run the same setup as an
  # initrd service after sysroot is mounted. Under systemd stage 1 the mounted
  # root is available at /sysroot rather than /mnt-root.
  boot.initrd.systemd.services.initrd-usb-overlay-store = {
    description = "Prepare USB squashfs-backed /nix/store overlay";
    requires = ["sysroot.mount"];
    after = ["sysroot.mount"];
    requiredBy = ["initrd-fs.target"];
    before = ["initrd-fs.target"];
    unitConfig.DefaultDependencies = false;
    serviceConfig.Type = "oneshot";
    path = with pkgs; [
      coreutils
      util-linux
    ];
    script = ''
      mkdir -p /sysroot/nix/.ro-store /sysroot/nix/.rw-store
      mount -t squashfs -o loop,ro /sysroot/nix-store.squashfs /sysroot/nix/.ro-store
      mount -t tmpfs -o mode=0755,size=2G tmpfs /sysroot/nix/.rw-store
      mkdir -m 0755 -p /sysroot/nix/.rw-store/upper /sysroot/nix/.rw-store/work
      mount -t overlay overlay \
        -o lowerdir=/sysroot/nix/.ro-store,upperdir=/sysroot/nix/.rw-store/upper,workdir=/sysroot/nix/.rw-store/work \
        /sysroot/nix/store
    '';
  };

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
