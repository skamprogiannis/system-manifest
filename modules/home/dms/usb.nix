{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: let
  dmsBasePackage = inputs.dms.packages.${pkgs.stdenv.hostPlatform.system}.dms-shell;
  patchDmsPackage = import ./patch-package.nix {inherit pkgs;};
  dmsPatches = import ./common-patches.nix;
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
    pythonPrelude = dmsPatches.pythonPrelude;
    replacementsPython = dmsPatches.usbReplacementsPython;
  };
in {
  systemd.user.services.dms.Service.Environment = [
    "QS_NO_GL=1"
    "QT_QUICK_BACKEND=software"
    "QSG_RENDER_LOOP=basic"
  ];

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
}
