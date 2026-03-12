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
          # col.active_border and col.inactive_border set dynamically by matugen via colors.conf
        };

        decoration = {
          rounding = 10;
          active_opacity = 1.0;
          inactive_opacity = 1.0;

          dim_inactive = true;
          dim_strength = 0.15;
          blur = {
            enabled = true;
            size = 3;
            passes = 2;
            noise = 0.02;
            contrast = 0.9;
            xray = false;
            new_optimizations = true;
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
          # --- System & Apps ---
          "$mod, Return, exec, ghostty"
          "$mod, b, exec, brave"
          "$mod, x, killactive,"
          "$mod, m, exec, ghostty -e spotify_player"
          "$mod, e, exec, nautilus"
          "$mod, v, togglefloating,"
          "$mod, f, fullscreen,"
          "$mod, d, exec, dms ipc call spotlight toggle"
          "$mod SHIFT, v, exec, dms ipc call clipboard toggle"
          "$mod, p, pseudo,"
          "$mod, backslash, togglesplit,"
          "$mod, g, togglegroup,"
          "$mod, Tab, changegroupactive, f"

          # --- Navigation ---
          "$mod, h, ${navL}"
          "$mod, l, ${navR}"
          "$mod, k, movefocus, u"
          "$mod, j, movefocus, d"
          "$mod, Left, movefocus, l"
          "$mod, Right, movefocus, r"
          "$mod, Up, movefocus, u"
          "$mod, Down, movefocus, d"

          # --- Window Movement ---
          "$mod SHIFT, h, movewindow, l"
          "$mod SHIFT, l, movewindow, r"
          "$mod SHIFT, k, movewindow, u"
          "$mod SHIFT, j, movewindow, d"
          "$mod SHIFT, Left, movewindow, mon:-1"
          "$mod SHIFT, Right, movewindow, mon:+1"

          # --- Workspaces ---
          "$mod, 1, workspace, 1"
          "$mod, 2, workspace, 2"
          "$mod, 3, workspace, 3"
          "$mod, 4, workspace, 4"
          "$mod, 5, workspace, 5"
          "$mod, 6, workspace, 6"
          "$mod, 7, workspace, 7"
          "$mod, 8, workspace, 8"
          "$mod, 9, workspace, 9"
          "$mod, 0, workspace, 10"
          "$mod SHIFT, 1, movetoworkspace, 1"
          "$mod SHIFT, 2, movetoworkspace, 2"
          "$mod SHIFT, 3, movetoworkspace, 3"
          "$mod SHIFT, 4, movetoworkspace, 4"
          "$mod SHIFT, 5, movetoworkspace, 5"
          "$mod SHIFT, 6, movetoworkspace, 6"
          "$mod SHIFT, 7, movetoworkspace, 7"
          "$mod SHIFT, 8, movetoworkspace, 8"
          "$mod SHIFT, 9, movetoworkspace, 9"
          "$mod SHIFT, 0, movetoworkspace, 10"

          # --- Special Workspaces ---
          "$mod, grave, togglespecialworkspace, music"
          "$mod SHIFT, grave, movetoworkspace, special:music"

          # --- Screenshots ---
          ", Print, exec, screenshot-path region path"
          "SHIFT, Print, exec, dms screenshot region"
          "CONTROL, Print, exec, screenshot-path window path"
          "CONTROL SHIFT, Print, exec, dms screenshot window"
          "ALT, Print, exec, screenshot-path full path"
          "ALT SHIFT, exec, dms screenshot full"

          # --- Screen Recording ---
          "$mod, r, exec, screenrecord region"
          "$mod SHIFT, r, exec, screenrecord full"

          # --- DMS IPC Controls ---
          "$mod, n, exec, dms ipc call notifications toggle"
          "$mod SHIFT, n, exec, dms ipc call notifications clearAll && echo '{\"notifications\": []}' > ~/.cache/DankMaterialShell/notification_history.json"
          "$mod, BackSpace, exec, dms ipc call notifications dismissAllPopups"
          "$mod, o, exec, dms ipc call hypr toggleOverview"
          "$mod, Escape, exec, dms ipc call lock lock"
          "$mod, s, exec, dms ipc call settings toggle"
          "$mod, q, exec, dms ipc call powermenu toggle"
        ];

        windowrule = [
          "opacity 1.0 override, match:class ^(mpv|vlc|imv|feh)$"
          "opacity 1.0 override, match:title ^(Picture-in-Picture)$"
          # Center credential/auth dialogs so they don't spawn between monitors
          "float 1, match:class ^(pinentry|pinentry-gtk-2|pinentry-gnome3|ssh-askpass|git-askpass)$"
          "center 1, match:class ^(pinentry|pinentry-gtk-2|pinentry-gnome3|ssh-askpass|git-askpass)$"
          "size 400 200, match:class ^(pinentry|pinentry-gtk-2|pinentry-gnome3|ssh-askpass|git-askpass)$"
          # Hide WE screenshot windows (we-sync offscreen rendering)
          "workspace special:wesync silent, match:title ^(wallpaperengine)$"
        ];


        bindr = [];

      };

      extraConfig = ''
        $terminal = ghostty

        plugin:hyprglass {
          enabled = 1
          default_theme = light
          default_preset = default
          blur_strength = 2.5
          blur_iterations = 4
          tint_color = 0xffffff08
          specular_strength = 0.5
          edge_thickness = 0.04
          lens_distortion = 0.1
          light:brightness = 1.02
          light:contrast = 0.95
          light:saturation = 1.0
          light:vibrancy = 0.05
          light:adaptive_boost = 0.05
          light:adaptive_dim = 0.0
        }

      '';
    };
  };
}
