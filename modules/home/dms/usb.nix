{
  pkgs,
  lib,
  inputs,
  skwdQsgRhiBackend,
  ...
}: let
  dmsBasePackage = inputs.dms.packages.${pkgs.stdenv.hostPlatform.system}.dms-shell;
  skwdWallPackage = import ../skwd-wall-package.nix {
    inherit pkgs inputs;
    qsgRhiBackend = skwdQsgRhiBackend;
  };
  patchDmsPackage = import ./patch-package.nix {inherit pkgs;};
  dmsPatches = import ./common-patches.nix {inherit skwdWallPackage;};
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
  dmsHyprlandEventWatchdog = pkgs.writeShellScript "dms-hyprland-event-watchdog" ''
    set -eu

    ${pkgs.systemd}/bin/journalctl --user -b -n 0 -f -u dms.service -o cat |
      while IFS= read -r line; do
        case "$line" in
          *"Hyprland event socket error: QLocalSocket::PeerClosedError"*)
            echo "dms-hyprland-event-watchdog: restarting dms.service after Hyprland event socket disconnect" >&2
            ${pkgs.systemd}/bin/systemctl --user restart dms.service
            ${pkgs.coreutils}/bin/sleep 5
            ;;
        esac
      done
  '';
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
    -- USB displays are hardware-specific; let Hyprland auto-select the panel.
    hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "1" })
  '';

  systemd.user.services.dms-hyprland-event-watchdog = {
    Unit = {
      Description = "Restart DMS if its Hyprland event socket disconnects";
      PartOf = ["hyprland-session.target"];
    };
    Service = {
      Type = "simple";
      ExecStart = "${dmsHyprlandEventWatchdog}";
      Restart = "always";
      RestartSec = 2;
    };
    Install.WantedBy = ["hyprland-session.target"];
  };
}
