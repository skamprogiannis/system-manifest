{
  config,
  pkgs,
  lib,
  ...
}: {
  imports = [
    ../../home.nix
  ];

  wayland.windowManager.hyprland.settings = {
    workspace = [
      "1, monitor:DP-1, default:true"
      "2, monitor:DP-1"
      "3, monitor:DP-1"
      "4, monitor:DP-1"
      "5, monitor:DP-1"
      "6, monitor:DP-1"
      "7, monitor:DP-1"
      "8, monitor:DP-1"
      "9, monitor:DP-1"
      "10, monitor:HDMI-A-1, default:true"
    ];
  };

  programs.dank-material-shell.settings = {
    displayProfiles = {
      hyprland = {
        desktop = {
          id = "desktop";
          name = "Desktop";
          outputSet = [
            "Samsung Electric Company S24E510C"
            "BNQ BenQ XL2411Z"
          ];
          createdAt = 1;
          updatedAt = 1;
        };
        gaming = {
          id = "gaming";
          name = "Gaming (BenQ VRR)";
          outputSet = [
            "Samsung Electric Company S24E510C"
            "BNQ BenQ XL2411Z"
          ];
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
      monitor = desc:Samsung Electric Company S24E510C 0x3042524B, 1920x1080@60.000, 0x0, 1, vrr, 0
      monitor = desc:BNQ BenQ XL2411Z 54G01103SL0, 1920x1080@60.000, 1920x0, 1, vrr, 0
    '';

    "hypr/dms/profiles/desktop.conf".text = ''
      monitor = desc:Samsung Electric Company S24E510C 0x3042524B, 1920x1080@60.000, 0x0, 1, vrr, 0
      monitor = desc:BNQ BenQ XL2411Z 54G01103SL0, 1920x1080@60.000, 1920x0, 1, vrr, 0
    '';

    "hypr/dms/profiles/gaming.conf".text = ''
      monitor = desc:Samsung Electric Company S24E510C 0x3042524B, 1920x1080@60.000, 0x0, 1, vrr, 0
      monitor = desc:BNQ BenQ XL2411Z 54G01103SL0, 1920x1080@60.000, 1920x0, 1, vrr, 1
    '';
  };

  programs.zellij.settings.default_layout = "dev";
}
