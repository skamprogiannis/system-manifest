{ctx}: let
  inherit (ctx) pkgs updateUsbSourceDir;
  inherit (pkgs) lib;

  # These are small, bootable NixOS systems; the desktop/USB application closure
  # is intentionally not required to test publication and rollback ordering.
  bootSystem = generation:
    (import (pkgs.path + "/nixos/lib/eval-config.nix") {
      system = pkgs.stdenv.hostPlatform.system;
      modules = [
        (pkgs.path + "/nixos/modules/testing/test-instrumentation.nix")
        ({...}: {
          nixpkgs.pkgs = pkgs;
          system.stateVersion = "26.05";
          system.configurationRevision = generation;
          networking.hostName = "usb-update-target";
          documentation.enable = false;
          documentation.nixos.enable = false;
          boot.initrd.systemd.enable = true;
          boot.initrd.availableKernelModules = ["virtio_pci" "virtio_blk"];
          boot.initrd.kernelModules = ["loop" "squashfs" "overlay"];
          boot.kernelParams = ["console=ttyS0"];
          boot.loader.grub = {
            enable = true;
            device = "nodev";
            efiSupport = true;
            efiInstallAsRemovable = true;
            configurationLimit = 2;
            extraConfig = "serial; terminal_output serial";
          };
          boot.loader.efi.canTouchEfiVariables = false;
          fileSystems = {
            "/" = {
              device = "/dev/disk/by-label/usb-test-root";
              fsType = "ext4";
            };
            "/boot" = {
              device = "/dev/disk/by-label/USBTESTBOOT";
              fsType = "vfat";
            };
            "/nix/.ro-store" = {
              device = "/sysroot/nix-store.squashfs";
              fsType = "squashfs";
              options = ["loop"];
              neededForBoot = true;
            };
            "/nix/.rw-store" = {
              fsType = "tmpfs";
              options = ["mode=0755" "size=128M"];
              neededForBoot = true;
            };
            "/nix/store" = {
              overlay = {
                lowerdir = ["/nix/.ro-store"];
                upperdir = "/nix/.rw-store/store";
                workdir = "/nix/.rw-store/work";
              };
              depends = ["/nix/.ro-store" "/nix/.rw-store"];
              neededForBoot = true;
            };
          };
          environment.etc."usb-update-generation".text = generation;
          users.users.stefan.isNormalUser = true;
          nix.settings = {
            substituters = lib.mkForce [];
            auto-optimise-store = false;
          };
        })
      ];
    }).config.system.build.toplevel;

  oldSystem = bootSystem "usb-update-old";
  newSystem = bootSystem "usb-update-new";
  shared = pkgs.runCommand "usb-update-shared" {} ''
    mkdir -p "$out"
    dd if=/dev/zero of="$out/payload" bs=1024 count=1024 status=none
  '';
  obsolete = pkgs.writeText "usb-update-obsolete" "Only the oldest generation references this package.";
  fixture = name: extra:
    pkgs.runCommand "usb-update-${name}" {} ''
      mkdir -p "$out/sw/bin"
      ln -s '${pkgs.nix}/bin/nix-store' "$out/sw/bin/nix-store"
      printf '#!/bin/sh\nexit 0\n' > "$out/init"
      chmod +x "$out/init"
      printf '%s\n' '${shared}' '${extra}' '${name}' > "$out/references"
    '';
  oldestFixture = fixture "oldest" obsolete;
  oldFixture = fixture "old" "";
  newFixture = fixture "new" "";
  integrationSources = pkgs.linkFarm "usb-update-integration-sources" (
    map (name: {
      inherit name;
      path = updateUsbSourceDir + "/${name}";
    }) ["phases.sh" "metadata.sh" "staging.sh" "squashfs.sh" "transaction.sh"]
  );
  harness = pkgs.writeShellScript "usb-update-integration" ''
    export USB_UPDATE_TEST_VM=1
    export UPDATE_USB_SOURCE_DIR=${integrationSources}
    export OLD_SYSTEM=${oldSystem}
    export NEW_SYSTEM=${newSystem}
    export FIXTURE_SHARED=${shared}
    export FIXTURE_OBSOLETE=${obsolete}
    export FIXTURE_OLDEST=${oldestFixture}
    export FIXTURE_OLD=${oldFixture}
    export FIXTURE_NEW=${newFixture}
    export NIX_CONFIG='experimental-features = nix-command
    substituters =
    auto-optimise-store = false'
    exec ${pkgs.bash}/bin/bash ${./usb-update-integration.sh} "$@"
  '';
in {
  usb-update-integration = pkgs.testers.runNixOSTest {
    name = "usb-update-integration";
    globalTimeout = 2400;
    requiredFeatures.kvm = false;
    nodes = {
      installer = {
        virtualisation = {
          memorySize = 2048;
          cores = 2;
          diskSize = 3072;
          diskImage = "./usb-update-target.qcow2";
          emptyDiskImages = [3072];
          rootDevice = "/dev/vdb";
          fileSystems."/".autoFormat = true;
        };
        boot.kernelModules = ["loop" "squashfs" "overlay"];
        environment.systemPackages = with pkgs; [
          bash
          coreutils
          dosfstools
          e2fsprogs
          findutils
          gnugrep
          gnused
          gptfdisk
          jq
          nix
          nixos-install-tools
          squashfsTools
          util-linux
        ];
        system.extraDependencies = [oldSystem newSystem harness];
        nix.settings = {
          substituters = lib.mkForce [];
          auto-optimise-store = false;
          experimental-features = ["nix-command"];
        };
      };
      target = {
        virtualisation = {
          memorySize = 2048;
          cores = 2;
          diskSize = 3072;
          diskImage = "./usb-update-target.qcow2";
          useBootLoader = true;
          useEFIBoot = true;
          useDefaultFilesystems = false;
          efi.keepVariables = false;
          fileSystems."/" = {
            device = "/dev/disk/by-label/usb-test-root";
            fsType = "ext4";
          };
        };
      };
    };
    testScript = ''
      def run_installer(step, shutdown=True):
          installer.start()
          installer.wait_for_unit("multi-user.target")
          print(installer.succeed("${harness} " + step, timeout=900))
          if shutdown:
              installer.shutdown()

      def boot_generation(expected):
          target.state_dir = installer.state_dir
          target.start()
          target.wait_for_unit("multi-user.target", timeout=180)
          assert expected == target.succeed("cat /etc/usb-update-generation").strip()
          target.succeed("findmnt -n -o FSTYPE /nix/store | grep -x overlay")
          target.succeed("findmnt -n -o FSTYPE /nix/.ro-store | grep -x squashfs")
          target.shutdown()

      with subtest("real local-store staging, garbage collection, and rejected candidates"):
          run_installer("fixtures", shutdown=False)
      with subtest("initial squashfs system boots through removable EFI GRUB"):
          run_installer("initial")
          boot_generation("usb-update-old")
      with subtest("prepared update leaves the previous system bootable"):
          run_installer("prepare")
          boot_generation("usb-update-old")
      with subtest("interruption after image publication preserves the old boot"):
          run_installer("after-image")
          boot_generation("usb-update-old")
      with subtest("interruption after metadata exchange preserves the old boot"):
          run_installer("after-metadata")
          boot_generation("usb-update-old")
      with subtest("retry finishes publication and boots the new system"):
          run_installer("finish")
          boot_generation("usb-update-new")
      with subtest("retained rollback generation remains bootable"):
          run_installer("rollback")
          boot_generation("usb-update-old")
    '';
  };
}
