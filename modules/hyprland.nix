{
  config,
  pkgs,
  ...
}: {
  wayland.windowManager.hyprland = {
    enable = true;

    settings = {
      "$mod" = "SUPER";
      "$terminal" = "ghostty";
      "$menu" = "wofi --show drun";

      monitor = ",preferred,auto,1";
      exec-once = [
        "waybar"
        "dunst"
        "hyprpaper"
        "wl-paste --type text --watch cliphist store"
        "wl-paste --type image --watch cliphist store"
      ];

      env = [
        "XCURSOR_SIZE,24"
      ];

      input = {
        kb_layout = "us,gr";
        kb_options = "grp:alt_shift_toggle";
      };

      general = {
        gaps_in = 5;
        gaps_out = 10;
        border_size = 2;
        # The Cyberpunk Colors: Neon Pink active, Grey inactive
        "col.active_border" = "rgb(ff00ff) rgb(00ffff) 45deg";
        "col.inactive_border" = "rgba(595959aa)";
        layout = "dwindle";
      };

      decoration = {
        rounding = 10;
        blur = {
          enabled = true;
          size = 3;
          passes = 1;
        };
        # Shadow for depth
        shadow = {
          enabled = true;
          range = 4;
          render_power = 3;
          color = "rgba(1a1a1aee)";
        };
      };

      # Animations (Making it feel fast)
      animations = {
        enabled = true;
        bezier = "myBezier, 0.05, 0.9, 0.1, 1.05";
        animation = [
          "windows, 1, 7, myBezier"
          "windowsOut, 1, 7, default, popin 80%"
          "border, 1, 10, default"
          "fade, 1, 7, default"
          "workspaces, 1, 6, default"
        ];
      };

      dwindle = {
        pseudotile = true;
        preserve_split = true;
      };

      bind = [
        # Terminal
        "$mod, RETURN, exec, $terminal"

        # Window Management
        "$mod, Q, killactive,"

        "$mod, M, exit,"
        "$mod, E, exec, nautilus"
        "$mod, V, togglefloating,"
        "$mod, R, exec, $menu"

        # Clipboard Manager
        "$mod SHIFT, V, exec, cliphist list | wofi --dmenu | cliphist decode | wl-copy"
        "$mod, P, pseudo,"
        "$mod, J, togglesplit,"
        # Focus movement
        "$mod, left, movefocus, l"
        "$mod, right, movefocus, r"
        "$mod, up, movefocus, u"
        "$mod, down, movefocus, d"
      ];
    };
  };

  # Hyprland Ecosystem Packages
  home.packages = with pkgs; [
    waybar
    wofi
    dunst
    hyprpaper
  ];
}
