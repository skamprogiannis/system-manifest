{
  config,
  pkgs,
  lib,
  ...
}: {
  home.packages = with pkgs; [
    qt5.qtwayland
    qt6.qtwayland
  ];

  wayland.windowManager.hyprland = {
    enable = true;
    systemd = {
      enable = true;
      variables = ["--all"];
    };

    settings = {
      source = [
        "~/.config/hypr/dms/colors.conf"
        "~/.config/hypr/dms/cursor.conf"
        "~/.config/hypr/dms/layout.conf"
      ];
      "$mod" = "SUPER";

      env = [
        "XCURSOR_SIZE,${toString config.home.pointerCursor.size}"
        "XCURSOR_THEME,${config.home.pointerCursor.name}"
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
        "hyprctl setcursor ${config.home.pointerCursor.name} ${toString config.home.pointerCursor.size}"
        "wallpaper-hook &"
      ];

      misc = {
        disable_hyprland_logo = true;
        disable_splash_rendering = true;
        force_default_wallpaper = 0;
      };

      input = {
        kb_layout = "us,gr";
        kb_variant = "altgr-intl,simple";
        kb_options = "grp:win_space_toggle";
        resolve_binds_by_sym = 1;
      };

      general = {
        gaps_in = 5;
        gaps_out = 10;
        border_size = 2;
        layout = "dwindle";
        "col.active_border" = "rgba(80560099)"; # Fallback dynamic color
      };

      decoration = {
        rounding = 10;
        active_opacity = 0.75; # More glassy focused window
        inactive_opacity = 0.85; # More glassy background window
        dim_inactive = true;
        dim_strength = 0.2;
        blur = {
          enabled = true;
          size = 5;
          passes = 4;
          new_optimizations = true;
          ignore_opacity = true;
          xray = false; # Allow scratchpad transparency
          vibrancy = 1.0;
          brightness = 1.2;
          contrast = 1.2;
          noise = 0.03;
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

      bindel = [
        ", XF86AudioRaiseVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+"
        ", XF86AudioLowerVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"
        ", XF86AudioMute, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"
        ", XF86AudioPrev, exec, dms ipc call mpris previous"
        ", XF86AudioPlay, exec, dms ipc call mpris playPause"
        ", XF86AudioNext, exec, dms ipc call mpris next"
      ];

      bind = [
        # --- System & Apps (Keycodes for cross-layout support) ---
        "$mod, code:36, exec, ghostty" # Return
        "$mod, code:56, exec, brave" # b
        "$mod, code:53, killactive," # x
        "$mod, code:58, exec, ghostty -e spotify_player" # m
        "$mod, code:26, exec, nautilus" # e
        "$mod, code:55, togglefloating," # v
        "$mod, code:41, fullscreen," # f
        "$mod, code:27, exec, dms ipc call spotlight toggle" # r
        "$mod SHIFT, code:55, exec, dms ipc call clipboard toggle" # Super+Shift+v
        "$mod, code:33, pseudo," # p
        "$mod, code:51, togglesplit," # \
        "$mod, code:42, togglegroup," # g
        "$mod, code:23, changegroupactive, f" # Tab

        # --- Navigation (with Workspace Overflow) ---
        "$mod, code:43, exec, hypr-nav l" # h
        "$mod, code:46, exec, hypr-nav r" # l
        "$mod, code:45, movefocus, u" # k
        "$mod, code:44, movefocus, d" # j
        "$mod, code:113, movefocus, l" # Left
        "$mod, code:114, movefocus, r" # Right
        "$mod, code:111, movefocus, u" # Up
        "$mod, code:116, movefocus, d" # Down

        # --- Window Movement ---
        "$mod SHIFT, code:43, movewindow, l" # H
        "$mod SHIFT, code:46, movewindow, r" # L
        "$mod SHIFT, code:45, movewindow, u" # K
        "$mod SHIFT, code:44, movewindow, d" # J
        "$mod SHIFT, code:113, movewindow, mon:-1" # Left
        "$mod SHIFT, code:114, movewindow, mon:+1" # Right

        # --- Workspaces ---
        "$mod, code:10, workspace, 1"
        "$mod, code:11, workspace, 2"
        "$mod, code:12, workspace, 3"
        "$mod, code:13, workspace, 4"
        "$mod, code:14, workspace, 5"
        "$mod, code:15, workspace, 6"
        "$mod, code:16, workspace, 7"
        "$mod, code:17, workspace, 8"
        "$mod, code:18, workspace, 9"
        "$mod, code:19, workspace, 10"
        "$mod SHIFT, code:10, movetoworkspace, 1"
        "$mod SHIFT, code:11, movetoworkspace, 2"
        "$mod SHIFT, code:12, movetoworkspace, 3"
        "$mod SHIFT, code:13, movetoworkspace, 4"
        "$mod SHIFT, code:14, movetoworkspace, 5"
        "$mod SHIFT, code:15, movetoworkspace, 6"
        "$mod SHIFT, code:16, movetoworkspace, 7"
        "$mod SHIFT, code:17, movetoworkspace, 8"
        "$mod SHIFT, code:18, movetoworkspace, 9"
        "$mod SHIFT, code:19, movetoworkspace, 10"

        # --- Special Workspaces & Screenshots ---
        "$mod, code:49, togglespecialworkspace, music" # `
        "$mod SHIFT, code:49, movetoworkspace, special:music" # ~
        ", Print, exec, screenshot-path region path"
        "SHIFT, Print, exec, dms screenshot region"
        "CONTROL, Print, exec, screenshot-path window path"
        "CONTROL SHIFT, Print, exec, dms screenshot window"
        "ALT, Print, exec, screenshot-path full path"
        "ALT SHIFT, Print, exec, dms screenshot full"

        # --- DMS IPC Controls ---
        "$mod, code:57, exec, dms ipc call notifications toggle" # n
        "$mod SHIFT, code:57, exec, dms ipc call notifications clearAll" # N
        "$mod, code:22, exec, dms ipc call notifications dismissAllPopups" # Backspace
        "$mod, code:32, exec, dms ipc call hypr toggleOverview" # o
        "$mod, code:9, exec, dms ipc call lock lock" # Escape
        "$mod, code:39, exec, dms ipc call settings toggle" # s
        "$mod, code:24, exec, dms ipc call powermenu toggle" # q
      ];

      windowrule = [
        "opacity 0.8 0.8, match:class ^(org.gnome.baobab)$"
      ];

      layerrule = [
        "blur, quickshell"
        "blur, dms:bar"
        "ignorezero, quickshell"
        "ignorezero, dms:bar"
      ];

      bindr = [];
    };

    extraConfig = ''
      $terminal = ghostty
    '';
  };
}
