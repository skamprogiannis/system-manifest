{
  pkgs,
  lib,
  inputs,
  ...
}: let
  dmsBasePackage = inputs.dms.packages.${pkgs.stdenv.hostPlatform.system}.dms-shell;
  patchDmsPackage = import ./patch-package.nix {inherit pkgs;};
  dmsPatches = import ./common-patches.nix {};
  emptyScreenPreferences = lib.genAttrs [
    "notifications"
    "osd"
    "toast"
    "notepad"
  ] (_: []);
  disabledTimeout = lib.mkForce 0;
  shortLockTimeout = lib.mkForce 600;
  usbDmsPackage = patchDmsPackage {
    package = dmsBasePackage;
    replacementsPython = dmsPatches.usbReplacementsPython;
  };
in {
  programs.dank-material-shell = {
    package = lib.mkForce usbDmsPackage;
    settings = {
      displayProfileAutoSelect = lib.mkForce true;
      screenPreferences = lib.mkForce emptyScreenPreferences;
      acLockTimeout = shortLockTimeout;
      acMonitorTimeout = disabledTimeout;
      acSuspendTimeout = disabledTimeout;
      batteryLockTimeout = shortLockTimeout;
      batteryMonitorTimeout = disabledTimeout;
      batterySuspendTimeout = disabledTimeout;
    };
  };

  xdg.configFile."hypr/dms/outputs.lua".text = ''
    -- Keep the default lab display behavior.
    hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "1" })
  '';

  # DMS rewrites outputs.lua on startup; apply hardware exceptions afterwards.
  xdg.configFile."hypr/system-manifest/usb-outputs.lua".text = ''
    hl.monitor({ output = "desc:Samsung Display Corp. 0x4154", mode = "preferred", position = "auto", scale = "2" })
  '';
  wayland.windowManager.hyprland.extraConfig = lib.mkAfter ''
    require("system-manifest.usb-outputs")
  '';
}
