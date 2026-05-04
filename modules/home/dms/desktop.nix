{...}: let
  samsungOutput = "Samsung Electric Company S24E510C";
  benqOutput = "BNQ BenQ XL2411Z";
  desktopOutputSet = [
    samsungOutput
    benqOutput
  ];
  samsungMonitor = "desc:Samsung Electric Company S24E510C 0x3042524B, 1920x1080@60.000, 0x0, 1, vrr, 0";
  benqMonitor = vrr: "desc:BNQ BenQ XL2411Z 54G01103SL0, 1920x1080@60.000, 1920x0, 1, vrr, ${toString vrr}";
  mkProfileText = benqVrr: ''
    monitor = ${samsungMonitor}
    monitor = ${benqMonitor benqVrr}
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
    "hypr/dms/outputs.conf".text = ''
      # Declarative DMS output profile (desktop baseline)
      ${mkProfileText 0}
    '';

    "hypr/dms/profiles/desktop.conf".text = mkProfileText 0;

    "hypr/dms/profiles/gaming.conf".text = mkProfileText 1;
  };
}
