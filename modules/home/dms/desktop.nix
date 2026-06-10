{...}: let
  samsungOutput = "Samsung Electric Company S24E510C";
  benqOutput = "BNQ BenQ XL2411Z";
  desktopOutputSet = [
    samsungOutput
    benqOutput
  ];
  samsungMonitor = {
    output = "desc:Samsung Electric Company S24E510C 0x3042524B";
    mode = "1920x1080@60.000";
    position = "0x0";
    vrr = 0;
  };
  benqMonitor = vrr: {
    output = "desc:BNQ BenQ XL2411Z 54G01103SL0";
    mode = "1920x1080@60.000";
    position = "1920x0";
    inherit vrr;
  };
  mkMonitorLua = monitor: ''hl.monitor({ output = "${monitor.output}", mode = "${monitor.mode}", position = "${monitor.position}", scale = "1", vrr = ${toString monitor.vrr} })'';
  mkMonitorHyprlang = monitor: "monitor = ${monitor.output}, ${monitor.mode}, ${monitor.position}, 1, vrr, ${toString monitor.vrr}";
  mkLuaProfileText = benqVrr: ''
    ${mkMonitorLua samsungMonitor}
    ${mkMonitorLua (benqMonitor benqVrr)}
  '';
  mkLegacyProfileText = benqVrr: ''
    ${mkMonitorHyprlang samsungMonitor}
    ${mkMonitorHyprlang (benqMonitor benqVrr)}
  '';
in {
  programs.dank-material-shell.settings = {
    displayProfiles = {
      hyprland = {
        desktop = {
          id = "desktop";
          name = "Desktop";
          outputSet = desktopOutputSet;
          createdAt = 1;
          updatedAt = 1;
        };
        gaming = {
          id = "gaming";
          name = "Gaming (BenQ VRR)";
          outputSet = desktopOutputSet;
          createdAt = 2;
          updatedAt = 2;
        };
      };
    };
    activeDisplayProfile.hyprland = "desktop";
  };

  xdg.configFile = {
    "hypr/dms/outputs.lua".text = ''
      -- Declarative DMS output profile (desktop baseline)
      ${mkLuaProfileText 0}
    '';

    "hypr/dms/profiles/desktop.conf".text = mkLegacyProfileText 0;

    "hypr/dms/profiles/gaming.conf".text = mkLegacyProfileText 1;
  };
}
