{
  config,
  pkgs,
  lib,
  ...
}: let
  usb = import ../../../shared/usb-constants.nix;
  cfg = config.system_manifest.scripts;
in {
  options.system_manifest.scripts = {
    enableSteamHostScratch = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Expose the temporary Steam client and state checkpoint helper on USB hosts.";
    };

    enableSetupPersistentUsb = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Expose the setup-persistent-usb helper in the current host profile.";
    };

    enableUpdateUsb = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Expose the update-usb helper in the current host profile.";
    };
  };

  config.home.packages =
    [
      (import ./host-scratch.nix {inherit pkgs;})
      (import ./store-status.nix {inherit pkgs;})
    ]
    ++ lib.optionals cfg.enableSteamHostScratch [
      (import ./steam-host-scratch.nix {inherit pkgs;})
    ]
    ++ lib.optionals cfg.enableSetupPersistentUsb [
      (import ./setup-persistent-usb.nix {inherit pkgs usb;})
    ]
    ++ lib.optionals cfg.enableUpdateUsb [
      (import ./update-usb.nix {inherit pkgs usb;})
    ];
}
