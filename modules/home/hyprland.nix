{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: let
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
      pkgs.glslang
      pkgs.libxcb
      pkgs.libxcb-wm
      pkgs.libxcb-errors
    ];
    postPatch = ''
      substituteInPlace src/Globals.hpp \
        --replace-fail '<hyprland/src/render/Framebuffer.hpp>' '<hyprland/src/render/gl/GLFramebuffer.hpp>' \
        --replace-fail 'CFramebuffer blurTempFramebuffer;' 'CGLFramebuffer blurTempFramebuffer;'

      substituteInPlace src/GlassDecoration.hpp \
        --replace-fail '<hyprland/src/render/Framebuffer.hpp>' '<hyprland/src/render/gl/GLFramebuffer.hpp>' \
        --replace-fail 'CFramebuffer m_sampleFramebuffer;' 'CGLFramebuffer m_sampleFramebuffer;' \
        --replace-fail 'void sampleBackground(CFramebuffer& sourceFramebuffer, CBox box);' 'void sampleBackground(IFramebuffer& sourceFramebuffer, CBox box);' \
        --replace-fail 'void applyGlassEffect(CFramebuffer& sourceFramebuffer, CFramebuffer& targetFramebuffer,' 'void applyGlassEffect(CGLFramebuffer& sourceFramebuffer, IFramebuffer& targetFramebuffer,'

      substituteInPlace src/GlassDecoration.cpp \
        --replace-fail 'void CGlassDecoration::sampleBackground(CFramebuffer& sourceFramebuffer, CBox box) {' $'void CGlassDecoration::sampleBackground(IFramebuffer& sourceFramebuffer, CBox box) {\n    auto* srcGLFramebuffer = dynamic_cast<CGLFramebuffer*>(&sourceFramebuffer);\n    if (!srcGLFramebuffer)\n        return;' \
        --replace-fail 'glBindFramebuffer(GL_READ_FRAMEBUFFER, sourceFramebuffer.getFBID());' 'glBindFramebuffer(GL_READ_FRAMEBUFFER, srcGLFramebuffer->getFBID());' \
        --replace-fail 'void CGlassDecoration::applyGlassEffect(CFramebuffer& sourceFramebuffer, CFramebuffer& targetFramebuffer,' 'void CGlassDecoration::applyGlassEffect(CGLFramebuffer& sourceFramebuffer, IFramebuffer& targetFramebuffer,' \
        --replace-fail 'glBindFramebuffer(GL_FRAMEBUFFER, targetFramebuffer.getFBID());' $'    auto* targetGLFramebuffer = dynamic_cast<CGLFramebuffer*>(&targetFramebuffer);\n    if (!targetGLFramebuffer)\n        return;\n\n    glBindFramebuffer(GL_FRAMEBUFFER, targetGLFramebuffer->getFBID());' \
        --replace-fail 'blurBackground(blurRadius, blurIterations, source->getFBID(), viewportWidth, viewportHeight);' $'        auto* sourceGLFramebuffer = dynamic_cast<CGLFramebuffer*>(source.get());\n        if (!sourceGLFramebuffer)\n            return;\n\n        blurBackground(blurRadius, blurIterations, sourceGLFramebuffer->getFBID(), viewportWidth, viewportHeight);'

      substituteInPlace Makefile \
        --replace-fail 'SOURCES = src/main.cpp src/GlassDecoration.cpp src/GlassPassElement.cpp src/PluginConfig.cpp src/ShaderManager.cpp' 'SOURCES = src/main.cpp src/GlassDecoration.cpp src/PluginConfig.cpp src/ShaderManager.cpp'

      substituteInPlace src/main.cpp \
        --replace-fail '    g_pHyprRenderer->m_renderPass.removeAllOfType("CGlassPassElement");' ""

      substituteInPlace src/GlassDecoration.cpp \
        --replace-fail '#include "GlassPassElement.hpp"' "" \
        --replace-fail '    CGlassPassElement::SGlassPassData data{this, alpha};' "" \
        --replace-fail '    g_pHyprRenderer->m_renderPass.add(makeUnique<CGlassPassElement>(data));' '    renderPass(monitor, alpha);' \
        --replace-fail 'g_pHyprOpenGL->m_renderData' 'g_pHyprRenderer->m_renderData' \
        --replace-fail 'g_pHyprRenderer->m_renderData.monitorProjection.projectBox(rawBox, transform, rawBox.rot)' 'g_pHyprRenderer->getBoxProjection(rawBox, transform)' \
        --replace-fail 'g_pHyprRenderer->m_renderData.projection.copy().multiply(matrix)' 'g_pHyprRenderer->projectBoxToTarget(rawBox, transform)'
    '';
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
    # Create empty DMS hyprland config placeholders if they don't exist yet.
    # Hyprland's source directive fails on missing files and these are only
    # generated by DMS at runtime (after Hyprland has already loaded).
    home.activation.ensureDmsHyprConfigs = lib.hm.dag.entryBefore ["checkLinkTargets"] ''
      mkdir -p "$HOME/.config/hypr/dms"
      for f in colors.conf cursor.conf layout.conf outputs.conf binds.conf windowrules.conf; do
        [ -f "$HOME/.config/hypr/dms/$f" ] || touch "$HOME/.config/hypr/dms/$f"
      done
    '';

    home.packages = with pkgs; [
      qt5.qtwayland
      qt6.qtwayland
      swaybg
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
          "~/.config/hypr/dms/outputs.conf"
          "~/.config/hypr/dms/binds.conf"
          "~/.config/hypr/dms/windowrules.conf"
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
          # Instant static wallpaper while DMS loads; killed after 8s
          ''sh -c 'wall=$(${pkgs.jq}/bin/jq -r ".wallpaperPath // empty" ~/.local/state/DankMaterialShell/session.json 2>/dev/null); [ -f "$wall" ] && swaybg -i "$wall" -m fill & BGPID=$!; sleep 8; kill $BGPID 2>/dev/null' ''
          "hyprctl setcursor ${config.home.pointerCursor.name} ${toString config.home.pointerCursor.size}"
          "systemctl --user start wallpaper-hook.service"
          # home-manager user services show as "linked" in systemd and don't
          # auto-start on login; ensure they're running after Hyprland starts
          "systemctl --user start spotify-player.service"
          "systemctl --user start transmission-daemon.service"
        ];

        misc = {
          disable_hyprland_logo = true;
          disable_splash_rendering = true;
          force_default_wallpaper = 0;
          enable_anr_dialog = false;
          anr_missed_pings = 20;
          # Solid black background before wallpaper loads — avoids the
          # default grey/teal flash during login transition.
          background_color = "rgb(000000)";
        };

        ecosystem = {
          no_update_news = true;
          no_donation_nag = true;
        };

        debug = {
          # Suppress the wall of debug text visible on the TTY during startup
          disable_logs = true;
        };

        input = {
          kb_layout = "us,gr";
          kb_variant = "altgr-intl,simple";
          kb_options = "grp:win_space_toggle,caps:escape_shifted_capslock";
          resolve_binds_by_sym = false;
        };

        # Nvidia hardware cursors can bypass hide-on-keypress/inactivity behavior.
        # Force software cursors so Hyprland/DMS cursor-hide works consistently.
        cursor = {
          no_hardware_cursors = true;
        };

        general = {
          gaps_in = 5;
          gaps_out = 10;
          border_size = 2;
          layout = "dwindle";
          # col.active_border and col.inactive_border set dynamically by matugen via colors.conf
        };

        decoration = {
          rounding = 12;
          active_opacity = 1.0;
          inactive_opacity = 1.0;

          dim_inactive = true;
          dim_strength = 0.20;
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

        binde = [
          "$mod CTRL, h, resizeactive, -30 0"
          "$mod CTRL, l, resizeactive, 30 0"
          "$mod CTRL, k, resizeactive, 30 30"
          "$mod CTRL, j, resizeactive, -30 -30"
          "$mod CTRL, Left, resizeactive, -60 0"
          "$mod CTRL, Right, resizeactive, 60 0"
          "$mod CTRL, Up, resizeactive, 60 60"
          "$mod CTRL, Down, resizeactive, -60 -60"
          "$mod ALT, h, moveactive, -30 0"
          "$mod ALT, l, moveactive, 30 0"
          "$mod ALT, k, moveactive, 0 -30"
          "$mod ALT, j, moveactive, 0 30"
          "$mod ALT, Left, moveactive, -60 0"
          "$mod ALT, Right, moveactive, 60 0"
          "$mod ALT, Up, moveactive, 0 -60"
          "$mod ALT, Down, moveactive, 0 60"
        ];

        bind = [
          # --- System & Apps ---
          "$mod, Return, exec, ghostty"
          "$mod, b, exec, brave"
          "$mod, x, killactive,"
          "$mod, m, exec, ghostty -e spotify_player"
          "$mod, e, exec, ghostty -e yazi"
          "$mod, v, togglefloating,"
          "$mod, f, fullscreen,"
          "$mod, d, exec, dms ipc call spotlight toggle"
          "$mod, t, exec, dms ipc call notepad toggle"
          "$mod SHIFT, v, exec, dms ipc call clipboard toggle"
          "$mod, p, pseudo,"
          "$mod, backslash, layoutmsg, togglesplit"
          "$mod, g, togglegroup,"
          "$mod, Tab, changegroupactive, f"

          # --- Navigation ---
          "$mod, h, ${navL}"
          "$mod, l, ${navR}"
          "$mod, k, movefocus, u"
          "$mod, j, movefocus, d"
          "$mod, Left, focusmonitor, l"
          "$mod, Right, focusmonitor, r"
          "$mod, Up, focusmonitor, u"
          "$mod, Down, focusmonitor, d"

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

          # --- Screenshots (image to clipboard) ---
          ", Print, exec, dms screenshot region"
          "CONTROL, Print, exec, dms screenshot window"
          "ALT, Print, exec, dms screenshot full"

          # --- Screenshots (file path to clipboard) ---
          "SHIFT, Print, exec, screenshot-path-copy region"
          "CONTROL SHIFT, Print, exec, screenshot-path-copy window"
          "ALT SHIFT, Print, exec, screenshot-path-copy full"

          # --- Screen Recording ---
          "$mod, r, exec, kooha"

          # --- DMS IPC Controls ---
          "$mod, n, exec, dms ipc call notifications toggle"
          "$mod SHIFT, n, exec, dms ipc call notifications clearAll && echo '{\"notifications\": []}' > ~/.cache/DankMaterialShell/notification_history.json"
          "$mod, BackSpace, exec, dms ipc call notifications dismissAllPopups"
          "$mod, o, exec, dms ipc call hypr toggleOverview"
          "$mod, Escape, exec, dms ipc call lock lock"
          "$mod, s, exec, dms ipc call settings toggle"
          "$mod, q, exec, dms ipc call powermenu toggle"
          "$mod, w, exec, wallpaper-selector"
          "$mod SHIFT, w, exec, dms ipc call dash toggle wallpaper"
          "$mod SHIFT, o, exec, dms ipc call dash toggle overview"
          "$mod SHIFT, m, exec, dms ipc call dash toggle media"
          "$mod ALT, w, exec, dms ipc call dash toggle weather"
        ];

        windowrule = [
          "opacity 1.0 override, match:class ^(mpv|vlc|imv|feh)$"
          "opacity 1.0 override, match:title ^(Picture-in-Picture)$"
          # Keep Vesktop fully opaque at compositor level; transparent UI
          # comes from Vesktop's native RGBA setting to preserve text opacity.
          "opacity 1.0 override, match:class ^(vesktop)$"
          # Center credential/auth dialogs so they don't spawn between monitors
          "float 1, match:class ^(pinentry|pinentry-gtk-2|pinentry-gnome3|ssh-askpass|git-askpass)$"
          "center 1, match:class ^(pinentry|pinentry-gtk-2|pinentry-gnome3|ssh-askpass|git-askpass)$"
          "size 400 200, match:class ^(pinentry|pinentry-gtk-2|pinentry-gnome3|ssh-askpass|git-askpass)$"
          # Hide WE screenshot windows (wallpaper-engine-sync offscreen rendering)
          "workspace special:wesync silent, match:title ^(wallpaperengine)$"
        ];

        bindm = [
          "$mod, mouse:272, movewindow"
          "$mod, mouse:273, resizewindow"
        ];


        bindr = [];

      };

      extraConfig = ''
        $terminal = ghostty

        plugin:hyprglass {
          enabled = 1
          default_theme = light
          default_preset = default
          blur_strength = 2.8
          blur_iterations = 4
          tint_color = 0xffffff08
          specular_strength = 0.6
          edge_thickness = 0.05
          lens_distortion = 0.14
          refraction_strength = 0.7
          chromatic_aberration = 0.6
          fresnel_strength = 0.7
          light:brightness = 1.02
          light:contrast = 0.95
          light:saturation = 1.0
          light:vibrancy = 0.05
          light:adaptive_boost = 0.05
          light:adaptive_dim = 0.0
        }

        # Give DMS overlays/popouts compositor blur without increasing the
        # global blur strength for every window.
        layerrule = blur on, match:namespace ^dms:(notification-popup|toast|osd|control-center|notification-center-popout|clipboard-popout|dash|process-list-popout|modal|slideout)$

      '';
    };
  };
}
