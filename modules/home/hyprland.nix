{
  config,
  pkgs,
  hostType,
  lib,
  ...
}: {
  programs.dank-material-shell = {
    enable = true;
    systemd.enable = true;
    enableSystemMonitoring = true;
    enableDynamicTheming = true;
    enableClipboardPaste = true;
    enableCalendarEvents = true;
    enableVPN = true;
    enableAudioWavelength = true;
  };

  wayland.windowManager.hyprland = {
    enable = true;

    settings = {
      "$mod" = "SUPER";
      "$terminal" = "ghostty";

      monitor = if hostType == "desktop" then [
        "HDMI-A-1, 1920x1080@60, 0x0, 1"
        "DP-1, 1920x1080@60, 1920x0, 1"
      ] else [
        ",preferred,auto,1"
      ];

      workspace = if hostType == "desktop" then [
        "0, monitor:HDMI-A-1, default:true"
        "1, monitor:DP-1, default:true"
        "2, monitor:DP-1"
        "3, monitor:DP-1"
        "4, monitor:DP-1"
        "5, monitor:DP-1"
        "6, monitor:DP-1"
        "7, monitor:DP-1"
        "8, monitor:DP-1"
        "9, monitor:DP-1"
      ] else [];

      env = [
        "XCURSOR_SIZE,24"
      ];

      exec-once = if hostType == "desktop" then ["hyprctl dispatch moveworkspacetomonitor 1 DP-1"] else [];

      input = {
        kb_layout = "us,gr";
        kb_variant = "altgr-intl,";
        kb_options = "grp:win_space_toggle";
      };

      general = {
        gaps_in = 5;
        gaps_out = 10;
        border_size = 2;
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
        shadow = {
          enabled = true;
          range = 4;
          render_power = 3;
          color = "rgba(1a1a1aee)";
        };
      };

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
        "$mod, RETURN, exec, $terminal"
        "$mod, B, exec, brave"
        "$mod, Q, killactive,"
        "$mod, M, exit,"
        "$mod, E, exec, nautilus"
        "$mod, V, togglefloating,"
        "$mod, R, exec, dms ipc call spotlight toggle"
        "$mod SHIFT, V, exec, dms ipc call clipboard toggle"
        "$mod, P, pseudo,"
        "$mod, J, togglesplit,"
        "$mod, G, togglegroup,"
        "$mod, Tab, changegroupactive, f"
        "$mod, h, movefocus, l"
        "$mod, l, movefocus, r"
        "$mod, k, movefocus, u"
        "$mod, j, movefocus, d"
        "$mod, left, focusmonitor, -1"
        "$mod, right, focusmonitor, +1"
        "$mod SHIFT, left, movewindow, mon:-1"
        "$mod SHIFT, right, movewindow, mon:+1"
        "$mod SHIFT, h, movewindow, l"
        "$mod SHIFT, l, movewindow, r"
        "$mod SHIFT, k, movewindow, u"
        "$mod SHIFT, j, movewindow, d"
        "$mod, 0, workspace, 0"
        "$mod, 1, workspace, 1"
        "$mod, 2, workspace, 2"
        "$mod, 3, workspace, 3"
        "$mod, 4, workspace, 4"
        "$mod, 5, workspace, 5"
        "$mod, 6, workspace, 6"
        "$mod, 7, workspace, 7"
        "$mod, 8, workspace, 8"
        "$mod, 9, workspace, 9"
        "$mod SHIFT, 0, movetoworkspace, 0"
        "$mod SHIFT, 1, movetoworkspace, 1"
        "$mod SHIFT, 2, movetoworkspace, 2"
        "$mod SHIFT, 3, movetoworkspace, 3"
        "$mod SHIFT, 4, movetoworkspace, 4"
        "$mod SHIFT, 5, movetoworkspace, 5"
        "$mod SHIFT, 6, movetoworkspace, 6"
        "$mod SHIFT, 7, movetoworkspace, 7"
        "$mod SHIFT, 8, movetoworkspace, 8"
        "$mod SHIFT, 9, movetoworkspace, 9"
        # Special workspace (scratchpad) for Spotify
        "$mod, grave, togglespecialworkspace, music"
        "$mod SHIFT, grave, movetoworkspace, special:music"
        ", Print, exec, dms screenshot region"
        "SHIFT, Print, exec, dms screenshot full"
        "CONTROL, Print, exec, dms screenshot window"
        "$mod, N, exec, dms ipc call notifications toggle"
        "$mod, L, exec, dms ipc call lock lock"
        "$mod, S, exec, dms ipc call settings toggle"
        "$mod, X, exec, dms ipc call powermenu toggle"
      ];
    };
  };
}
