{
  config,
  pkgs,
  hostType,
  lib,
  ...
}: {
  programs.dank-material-shell = {
    enable = true;
    systemd.enable = false;
    enableSystemMonitoring = true;
    enableDynamicTheming = true;
    enableClipboardPaste = true;
    enableCalendarEvents = true;
    enableVPN = true;
    enableAudioWavelength = true;
    settings = {
      showSeconds = true;
      useAutoLocation = true;
      matugenScheme = "scheme-content";
      matugenPaletteFidelity = 1;
    };
  };

  wayland.windowManager.hyprland = {
    enable = true;

    settings = {
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
        "XCURSOR_THEME,Dracula-cursors"
        "WLR_NO_HARDWARE_CURSORS,1"
        "GDK_BACKEND,wayland,x11"
        "QT_QPA_PLATFORM,wayland;xcb"
        "CLUTTER_BACKEND,wayland"
        "ANKI_WAYLAND,1"
        "MOZ_ENABLE_WAYLAND,1"
        "XDG_CURRENT_DESKTOP,Hyprland"
        "XDG_SESSION_TYPE,wayland"
        "XDG_SESSION_DESKTOP,Hyprland"
      ];

      exec-once = [
        "hyprctl setcursor Dracula-cursors 24"
        "wallpaper-hook &"
        "dms run --session"
      ] ++ (if hostType == "desktop" then ["hyprctl dispatch moveworkspacetomonitor 1 DP-1"] else []);

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

      cursor = {
        no_hardware_cursors = true;
      };

      dwindle = {
        pseudotile = true;
        preserve_split = true;
      };

      bind = [
        "SUPER, RETURN, exec, ghostty"
        "SUPER, B, exec, brave"
        "SUPER, X, killactive,"
        "SUPER, M, exit,"
        "SUPER, E, exec, nautilus"
        "SUPER, V, togglefloating,"
        "SUPER, F, fullscreen,"
        "SUPER, R, exec, dms ipc call spotlight toggle"
        "SUPER SHIFT, V, exec, dms ipc call clipboard toggle"
        "SUPER, P, pseudo,"
        "SUPER, backslash, togglesplit,"
        "SUPER, G, togglegroup,"
        "SUPER, Tab, changegroupactive, f"
        "SUPER, h, movefocus, l"
        "SUPER, l, movefocus, r"
        "SUPER, k, movefocus, u"
        "SUPER, j, movefocus, d"
        "SUPER, left, focusmonitor, -1"
        "SUPER, right, focusmonitor, +1"
        "SUPER SHIFT, left, movewindow, mon:-1"
        "SUPER SHIFT, right, movewindow, mon:+1"
        "SUPER SHIFT, h, movewindow, l"
        "SUPER SHIFT, l, movewindow, r"
        "SUPER SHIFT, k, movewindow, u"
        "SUPER SHIFT, j, movewindow, d"
        "SUPER, 0, workspace, 0"
        "SUPER, 1, workspace, 1"
        "SUPER, 2, workspace, 2"
        "SUPER, 3, workspace, 3"
        "SUPER, 4, workspace, 4"
        "SUPER, 5, workspace, 5"
        "SUPER, 6, workspace, 6"
        "SUPER, 7, workspace, 7"
        "SUPER, 8, workspace, 8"
        "SUPER, 9, workspace, 9"
        "SUPER SHIFT, 0, movetoworkspace, 0"
        "SUPER SHIFT, 1, movetoworkspace, 1"
        "SUPER SHIFT, 2, movetoworkspace, 2"
        "SUPER SHIFT, 3, movetoworkspace, 3"
        "SUPER SHIFT, 4, movetoworkspace, 4"
        "SUPER SHIFT, 5, movetoworkspace, 5"
        "SUPER SHIFT, 6, movetoworkspace, 6"
        "SUPER SHIFT, 7, movetoworkspace, 7"
        "SUPER SHIFT, 8, movetoworkspace, 8"
        "SUPER SHIFT, 9, movetoworkspace, 9"
        # Special workspace (scratchpad) for Spotify
        "SUPER, grave, togglespecialworkspace, music"
        "SUPER SHIFT, grave, movetoworkspace, special:music"
        ", Print, exec, dms screenshot region"
        "SHIFT, Print, exec, dms screenshot full"
        "CONTROL, Print, exec, dms screenshot window"
        "SUPER, N, exec, dms ipc call notifications toggle"
        "SUPER, Escape, exec, dms ipc call lock lock"
        "SUPER, S, exec, dms ipc call settings toggle"
        "SUPER, Q, exec, dms ipc call powermenu toggle"
      ];

      bindr = [
        ", SUPER_L, exec, dms ipc call spotlight toggle"
      ];
    };

    extraConfig = ''
      $mod = SUPER
      $terminal = ghostty
    '';
  };
}
