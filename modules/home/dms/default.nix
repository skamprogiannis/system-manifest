{
  pkgs,
  inputs,
  ...
}: let
  dmsBasePackage = inputs.dms.packages.${pkgs.stdenv.hostPlatform.system}.dms-shell;
  patchDmsPackage = import ./patch-package.nix {inherit pkgs;};
  dmsPatches = import ./common-patches.nix;
  dmsPatchedPackage = patchDmsPackage {
    package = dmsBasePackage;
    pythonPrelude = dmsPatches.pythonPrelude;
    replacementsPython = dmsPatches.defaultReplacementsPython;
  };
in {
  imports = [
    inputs.dms.homeModules.dank-material-shell
    ./session-state.nix
    ./settings.nix
  ];

  programs.dank-material-shell = {
    enable = true;
    package = dmsPatchedPackage;
    systemd = {
      enable = true;
      target = "hyprland-session.target";
    };
    enableSystemMonitoring = true;
    enableDynamicTheming = true;
    enableClipboardPaste = true;
    enableCalendarEvents = false;
    enableVPN = true;
    enableAudioWavelength = true;
  };
}
