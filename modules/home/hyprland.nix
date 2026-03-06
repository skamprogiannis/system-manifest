{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: let
  cfg = config.wayland.windowManager.hyprland;
  hyprland-pkg = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;
  hyprglass-plugin = pkgs.stdenv.mkDerivation {
    pname = "hyprglass";
    version = "0.2.4";
    src = pkgs.fetchFromGitHub {
      owner = "hyprnux";
      repo = "hyprglass";
      rev = "0e82595ec5c1b04e30b559fe689f3ceae24bc3ef";
      hash = "sha256-i2NXWuvVM+n6m4kwfqVTUOpinNWJHhSQdzMPbMR/Bn8=";
    };
    nativeBuildInputs = with pkgs; [pkg-config];
    buildInputs = [
      hyprland-pkg
      pkgs.aquamarine.dev
      pkgs.hyprutils.dev
      pkgs.hyprgraphics.dev
      pkgs.hyprlang.dev
      pkgs.hyprcursor.dev
      pkgs.libdrm.dev
      pkgs.libGL.dev
      pkgs.libinput.dev
      pkgs.wayland.dev
      pkgs.wayland-protocols
      pkgs.libxkbcommon.dev
      pkgs.pixman
      pkgs.cairo
    ];
    NIX_CFLAGS_COMPILE = "-I${hyprland-pkg.dev}/include/hyprland/protocols -I${pkgs.libdrm.dev}/include/libdrm";
    buildPhase = "make all";
    installPhase = ''
      mkdir -p $out/lib
      cp hyprglass.so $out/lib/hyprglass.so
    '';
  };
  useHyprNav = config.system_manifest.navigation.wrapWorkspaces or false;
  navL =
    if useHyprNav
    then "exec, hypr-nav l"
    else "movefocus, l";
  navR =
    if useHyprNav
    then "exec, hypr-nav r"
    else "movefocus, r";
in {
  options.system_manifest.navigation.wrapWorkspaces = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Whether to use hypr-nav for workspace wrapping.";
  };

  config = {
    home.packages = with pkgs; [
      qt5.qtwayland
      qt6.qtwayland
    ];

    wayland.windowManager.hyprland = {
      enable = true;
      package = hyprland-pkg;
      systemd = {
        enable = true;
        variables = ["--all"];
      };

      plugins = ["${hyprglass-plugin}/lib/hyprglass.so"];

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
          "NIXOS_OZONE_WL,1"
          "XDG_CURRENT_DESKTOP,Hyprland"
          "XDG_SESSION_TYPE,wayland"
          "XDG_SESSION_DESKTOP,Hyprland"
        ];

        exec-once = [
          "hyprctl setcursor ${config.home.pointerCursor.name} ${toString config.home.pointerCursor.size}"
          "wallpaper-hook &"
          "systemctl --user start wallpaper-thumbnail-watcher.service"
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
          active_opacity = 1.0;
          inactive_opacity = 1.0;

          dim_inactive = true;
          dim_strength = 0.15;
          blur = {
            enabled = false;
          };
          shadow = {
            enabled = true;
            range = 10;
            render_power = 2;
            color = "rgba(0f1116aa)";
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
          "$mod, code:40, exec, dms ipc call spotlight toggle" # d
          "$mod SHIFT, code:55, exec, dms ipc call clipboard toggle" # Super+Shift+v
          "$mod, code:33, pseudo," # p
          "$mod, code:51, togglesplit," # \
          "$mod, code:42, togglegroup," # g
          "$mod, code:23, changegroupactive, f" # Tab

          # --- Layout-Agnostic App Shortcuts ---
          "CONTROL, code:44, sendshortcut, CONTROL, code:44" # Ctrl+J

          # --- Navigation (with Workspace Overflow) ---
          "$mod, code:43, ${navL}" # h
          "$mod, code:46, ${navR}" # l
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

          # --- Special Workspaces ---
          "$mod, code:49, togglespecialworkspace, music" # `
          "$mod SHIFT, code:49, movetoworkspace, special:music" # ~

          # --- Screenshots ---
          ", Print, exec, screenshot-path region path"
          "SHIFT, Print, exec, dms screenshot region"
          "CONTROL, Print, exec, screenshot-path window path"
          "CONTROL SHIFT, Print, exec, dms screenshot window"
          "ALT, Print, exec, screenshot-path full path"
          "ALT SHIFT, Print, exec, dms screenshot full"

          # --- Screen Recording ---
          "$mod, code:27, exec, screenrecord region" # r
          "$mod SHIFT, code:27, exec, screenrecord full" # R

          # --- DMS IPC Controls ---
          "$mod, code:57, exec, dms ipc call notifications toggle" # n
          "$mod SHIFT, code:57, exec, dms ipc call notifications clearAll && echo '{\"notifications\": []}' > ~/.cache/DankMaterialShell/notification_history.json" # N
          "$mod, code:22, exec, dms ipc call notifications dismissAllPopups" # Backspace
          "$mod, code:32, exec, dms ipc call hypr toggleOverview" # o
          "$mod, code:9, exec, dms ipc call lock lock" # Escape
          "$mod, code:39, exec, dms ipc call settings toggle" # s
          "$mod, code:24, exec, dms ipc call powermenu toggle" # q
        ];

        windowrule = [
          "opacity 1.0 override, match:class ^(mpv|vlc|imv|feh)$"
          "opacity 1.0 override, match:title ^(Picture-in-Picture)$"
          # Ghostty uses native background-opacity; compositor stays at 1.0
          # Vesktop uses Translucence CSS for glass; compositor stays at 1.0
          "opacity 0.75 override, match:class ^(brave-browser)$"
          "opacity 0.75 override, match:class ^(firefox)$"
          "opacity 0.75 override, match:class ^(org.gnome.Nautilus)$"
          "opacity 0.75 override, match:class ^(obsidian)$"
          "opacity 0.80 override, match:class ^(Mailspring)$"
          "opacity 0.75 override, match:class ^(pear-runtime)$"
          "opacity 0.85 override, match:class ^(protonvpn-app)$"
          # Center credential/auth dialogs so they don't spawn between monitors
          "float 1, match:class ^(pinentry|pinentry-gtk-2|pinentry-gnome3|ssh-askpass|git-askpass)$"
          "center 1, match:class ^(pinentry|pinentry-gtk-2|pinentry-gnome3|ssh-askpass|git-askpass)$"
          "size 400 200, match:class ^(pinentry|pinentry-gtk-2|pinentry-gnome3|ssh-askpass|git-askpass)$"
        ];


        bindr = [];

        "plugin:hyprglass" = {
          enabled = 1;
          default_theme = "dark";
          default_preset = "default";
          blur_strength = 2.0;
          refraction_strength = 0.6;
          chromatic_aberration = 0.5;
          fresnel_strength = 0.6;
          specular_strength = 0.8;
          glass_opacity = 1.0;
          edge_thickness = 0.06;
          # Dark theme processing - let more wallpaper color through
          "dark:brightness" = 0.95;
          "dark:saturation" = 0.95;
          "dark:adaptive_dim" = 0.10;
        };
      };

      extraConfig = ''
        $terminal = ghostty
      '';
    };
  };
}
