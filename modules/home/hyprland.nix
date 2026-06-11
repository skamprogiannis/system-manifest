{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: let
  hyprland-pkg = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;
  hyprlandLuaPkg = let
    joined = pkgs.symlinkJoin {
      name = "${hyprland-pkg.name}-lua-config";
      paths = [hyprland-pkg];
      passthru = hyprland-pkg.passthru or {};
      meta =
        (hyprland-pkg.meta or {})
        // {
          mainProgram = "Hyprland";
          outputsToInstall = ["out"];
        };
      postBuild = ''
        rm -f $out/bin/Hyprland $out/bin/hyprland $out/bin/start-hyprland

        cat > $out/bin/Hyprland <<'EOF'
        #!${pkgs.bash}/bin/bash
        set -euo pipefail

        has_config=0
        for arg in "$@"; do
          case "$arg" in
            --config|-c|--config=*|-c=*)
              has_config=1
              break
              ;;
          esac
        done

        if [ "$has_config" -eq 1 ]; then
          exec ${hyprland-pkg}/bin/Hyprland "$@"
        fi

        config_home="''${XDG_CONFIG_HOME:-$HOME/.config}"
        exec ${hyprland-pkg}/bin/Hyprland --config "$config_home/hypr/hyprland.lua" "$@"
        EOF
        chmod +x $out/bin/Hyprland

        ln -s Hyprland $out/bin/hyprland

        cat > $out/bin/start-hyprland <<'EOF'
        #!${pkgs.bash}/bin/bash
        exec "$(dirname "$0")/Hyprland" "$@"
        EOF
        chmod +x $out/bin/start-hyprland
      '';
    };
  in
    joined
    // {
      inherit (hyprland-pkg) version;
      override = _: joined;
    };
  hyprglass-plugin = pkgs.stdenv.mkDerivation {
    pname = "hyprglass";
    version = "0.6.3";
    src = pkgs.fetchFromGitHub {
      owner = "hyprnux";
      repo = "hyprglass";
      rev = "16553225226cd15b2b0e5c7319e5242b427df1b2";
      hash = "sha256-UeAnHPGBW+2iKbPZ0xWp1VPRI18SuEYRSUCFfn3OKrU=";
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
      pkgs.lua
      pkgs.libxcb
      pkgs.libxcb-wm
      pkgs.libxcb-errors
    ];
    postPatch = ''
      substituteInPlace \
        src/Globals.hpp \
        src/GlassDecoration.hpp \
        src/GlassLayerSurface.hpp \
        src/GlassRenderer.hpp \
        --replace-fail '<hyprland/src/render/Framebuffer.hpp>' '<hyprland/src/render/gl/GLFramebuffer.hpp>'
      substituteInPlace src/Globals.hpp \
        --replace-fail 'CMonitor*' 'Monitor::CMonitor*'
    '';
    NIX_CFLAGS_COMPILE = "-I${hyprland-pkg.dev}/include/hyprland/src -I${hyprland-pkg.dev}/include/hyprland/protocols -I${pkgs.libdrm.dev}/include/libdrm -I${pkgs.lua}/include";
    buildPhase = "make all";
    installPhase = ''
      mkdir -p $out/lib
      cp hyprglass.so $out/lib/hyprglass.so
    '';
  };

  hyprglassPluginPath = "${hyprglass-plugin}/lib/hyprglass.so";
  hyprglassSettings = [
    {
      key = "enabled";
      value = "1";
    }
    {
      key = "default_theme";
      value = "light";
    }
    {
      key = "default_preset";
      value = "default";
    }
    {
      key = "blur_strength";
      value = "2.2";
    }
    {
      key = "blur_iterations";
      value = "4";
    }
    {
      key = "tint_color";
      value = "0xffffff0c";
    }
    {
      key = "specular_strength";
      value = "0.45";
    }
    {
      key = "edge_thickness";
      value = "0.035";
    }
    {
      key = "lens_distortion";
      value = "0.02";
    }
    {
      key = "refraction_strength";
      value = "0.18";
    }
    {
      key = "chromatic_aberration";
      value = "0.04";
    }
    {
      key = "fresnel_strength";
      value = "0.45";
    }
    {
      key = "brightness";
      value = "1.06";
    }
    {
      key = "contrast";
      value = "1.03";
    }
    {
      key = "saturation";
      value = "1.03";
    }
    {
      key = "vibrancy";
      value = "0.06";
    }
  ];
  hyprglassLuaValue = value:
    if lib.hasPrefix "0x" value
    then value
    else if builtins.match "^-?[0-9]+(\\.[0-9]+)?$" value != null
    then value
    else builtins.toJSON value;
  hyprglassLuaConfig = ''
    hl.config({
      plugin = {
        hyprglass = {
          ${lib.concatStringsSep ",\n          " (
      map (
        setting: "${setting.key} = ${hyprglassLuaValue setting.value}"
      )
      hyprglassSettings
    )}
        }
      }
    })
  '';
  applyHyprglassSettings = pkgs.writeShellScript "apply-hyprglass-settings" ''
    set -u

    hyprctl=${lib.escapeShellArg "${hyprland-pkg}/bin/hyprctl"}
    plugin_path=${lib.escapeShellArg hyprglassPluginPath}

    if ! plugin_list="$("$hyprctl" plugin list 2>/dev/null)"; then
      exit 0
    fi

    case "$plugin_list" in
      *"$plugin_path"*|*"hyprglass"*) ;;
      *) "$hyprctl" plugin load "$plugin_path" >/dev/null 2>&1 || true ;;
    esac

    "$hyprctl" eval ${lib.escapeShellArg hyprglassLuaConfig} >/dev/null 2>&1 || true
  '';

  useHyprNav = config.system_manifest.navigation.wrapWorkspaces or false;
  lua = lib.generators.mkLuaInline;
  modKey = key: lua ''mod .. " + ${key}"'';
  execCallback = command: lua "hl.dsp.exec_cmd(${builtins.toJSON command})";
  bind = key: callback: {
    _args = [key callback];
  };
  bindWith = key: callback: options: {
    _args = [key callback options];
  };
  execBind = key: command: bind key (execCallback command);
  execBindWith = key: command: options: bindWith key (execCallback command) options;
  focusDirection = direction: lua ''hl.dsp.focus({ direction = ${builtins.toJSON direction} })'';
  focusMonitor = monitor: lua ''hl.dsp.focus({ monitor = ${builtins.toJSON monitor} })'';
  focusWorkspace = workspace: lua ''hl.dsp.focus({ workspace = ${builtins.toJSON workspace} })'';
  moveWindowDirection = direction: lua ''hl.dsp.window.move({ direction = ${builtins.toJSON direction} })'';
  moveWindowMonitor = monitor: lua ''hl.dsp.window.move({ monitor = ${builtins.toJSON monitor} })'';
  moveWindowPosition = x: y: lua ''hl.dsp.window.move({ x = ${toString x}, y = ${toString y}, relative = true })'';
  moveToWorkspace = workspace: follow: lua ''hl.dsp.window.move({ workspace = ${builtins.toJSON workspace}, follow = ${lib.boolToString follow} })'';
  resizeWindow = x: y: lua ''hl.dsp.window.resize({ x = ${toString x}, y = ${toString y}, relative = true })'';
  toggleSpecialWorkspace = name: lua ''hl.dsp.workspace.toggle_special(${builtins.toJSON name})'';
  fullscreen = mode: lua ''hl.dsp.window.fullscreen({ mode = ${builtins.toJSON mode}, action = "toggle" })'';
  workspaceKeys = [
    {
      key = "1";
      workspace = "1";
    }
    {
      key = "2";
      workspace = "2";
    }
    {
      key = "3";
      workspace = "3";
    }
    {
      key = "4";
      workspace = "4";
    }
    {
      key = "5";
      workspace = "5";
    }
    {
      key = "6";
      workspace = "6";
    }
    {
      key = "7";
      workspace = "7";
    }
    {
      key = "8";
      workspace = "8";
    }
    {
      key = "9";
      workspace = "9";
    }
    {
      key = "0";
      workspace = "10";
    }
  ];
  workspaceBinds = lib.flatten (
    map (
      entry: [
        (bind (modKey entry.key) (focusWorkspace entry.workspace))
        (bind (modKey "SHIFT + ${entry.key}") (moveToWorkspace entry.workspace true))
        (bind (modKey "CTRL + ${entry.key}") (moveToWorkspace entry.workspace false))
      ]
    )
    workspaceKeys
  );
  mediaBinds = [
    (execBindWith "XF86AudioRaiseVolume" "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+" {
      locked = true;
      repeating = true;
    })
    (execBindWith "XF86AudioLowerVolume" "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-" {
      locked = true;
      repeating = true;
    })
    (execBindWith "XF86AudioMute" "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle" {
      locked = true;
      repeating = true;
    })
    (execBindWith "XF86AudioPrev" "dms ipc call mpris previous" {
      locked = true;
      repeating = true;
    })
    (execBindWith "XF86AudioPlay" "dms ipc call mpris playPause" {
      locked = true;
      repeating = true;
    })
    (execBindWith "XF86AudioNext" "dms ipc call mpris next" {
      locked = true;
      repeating = true;
    })
  ];
  repeatBinds = [
    (bindWith (modKey "CTRL + h") (resizeWindow (-30) 0) {repeating = true;})
    (bindWith (modKey "CTRL + l") (resizeWindow 30 0) {repeating = true;})
    (bindWith (modKey "CTRL + k") (resizeWindow 30 30) {repeating = true;})
    (bindWith (modKey "CTRL + j") (resizeWindow (-30) (-30)) {repeating = true;})
    (bindWith (modKey "CTRL + Left") (resizeWindow (-60) 0) {repeating = true;})
    (bindWith (modKey "CTRL + Right") (resizeWindow 60 0) {repeating = true;})
    (bindWith (modKey "CTRL + Up") (resizeWindow 60 60) {repeating = true;})
    (bindWith (modKey "CTRL + Down") (resizeWindow (-60) (-60)) {repeating = true;})
    (bindWith (modKey "ALT + h") (moveWindowPosition (-30) 0) {repeating = true;})
    (bindWith (modKey "ALT + l") (moveWindowPosition 30 0) {repeating = true;})
    (bindWith (modKey "ALT + k") (moveWindowPosition 0 (-30)) {repeating = true;})
    (bindWith (modKey "ALT + j") (moveWindowPosition 0 30) {repeating = true;})
    (bindWith (modKey "ALT + Left") (moveWindowPosition (-60) 0) {repeating = true;})
    (bindWith (modKey "ALT + Right") (moveWindowPosition 60 0) {repeating = true;})
    (bindWith (modKey "ALT + Up") (moveWindowPosition 0 (-60)) {repeating = true;})
    (bindWith (modKey "ALT + Down") (moveWindowPosition 0 60) {repeating = true;})
  ];
  mouseBinds = [
    (bind (modKey "mouse:272") (lua "hl.dsp.window.drag()"))
    (bind (modKey "mouse:273") (lua "hl.dsp.window.resize()"))
  ];
  dmsBlurNamespaces = lib.concatStringsSep "|" [
    "spotlight"
    "app-launcher"
    "notification-popup"
    "toast"
    "osd"
    "control-center"
    "notification-center-popout"
    "notification-center-modal"
    "clipboard-popout"
    "clipboard-context-menu"
    "dash"
    "process-list-popout"
    "workspace-overview"
    "niri-overview-spotlight"
    "power-menu"
    "wifi-qrcode"
    "color-picker"
    "layout"
    "system-update"
    "battery"
    "vpn"
    "bluetooth-pairing"
    "input-modal"
    "confirm-modal"
    "mux"
    "filebrowser"
    "network-info"
    "keybinds"
    "dock-context-menu"
    "tray-overflow-menu"
    "tray-menu-window"
    "notepad-context-menu"
    "modal"
    "slideout"
  ];

  navL =
    if useHyprNav
    then execCallback "hypr-nav l"
    else focusDirection "left";
  navR =
    if useHyprNav
    then execCallback "hypr-nav r"
    else focusDirection "right";
in {
  options.system_manifest.navigation.wrapWorkspaces = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Whether to use hypr-nav for workspace wrapping.";
  };

  config = {
    # Replace Hyprland's autogenerated first-launch config so Home Manager can
    # link the declarative one on images that have already booted once.
    # Also create empty DMS include files before Hyprland loads them.
    home.activation.ensureHyprlandConfigState = lib.hm.dag.entryBefore ["checkLinkTargets"] ''
      cfg="$HOME/.config/hypr/hyprland.conf"
      if [ -f "$cfg" ] && ${pkgs.gnugrep}/bin/grep -q "AUTOGENERATED HYPR CONFIG" "$cfg"; then
        rm -f "$cfg"
      fi

      mkdir -p "$HOME/.config/hypr/dms"
      for f in colors.lua cursor.lua layout.lua binds.lua binds-user.lua windowrules.lua; do
        [ -f "$HOME/.config/hypr/dms/$f" ] || touch "$HOME/.config/hypr/dms/$f"
      done
    '';

    home.packages = with pkgs; [
      hyprpolkitagent
      qt5.qtwayland
      qt6.qtwayland
    ];

    home.sessionVariables = {
      GTK_IM_MODULE = "ibus";
      QT_IM_MODULE = "ibus";
      XMODIFIERS = "@im=ibus";
    };

    systemd.user.services.ibus-daemon = {
      Unit = {
        Description = "IBus input method daemon";
        After = ["hyprland-session.target"];
        PartOf = ["hyprland-session.target"];
      };
      Service = {
        Type = "simple";
        ExecStart = "${pkgs.ibus}/bin/ibus-daemon --xim --replace --verbose";
        Restart = "on-failure";
        RestartSec = "2";
      };
      Install = {
        WantedBy = ["hyprland-session.target"];
      };
    };

    wayland.windowManager.hyprland = {
      enable = true;
      package = hyprlandLuaPkg;
      configType = "lua";
      systemd = {
        enable = true;
        variables = ["--all"];
      };

      settings = {
        mod = {
          _var = "SUPER";
        };

        env = [
          {_args = ["XCURSOR_SIZE" (toString config.home.pointerCursor.size)];}
          {_args = ["XCURSOR_THEME" config.home.pointerCursor.name];}
          {_args = ["GDK_BACKEND" "wayland,x11"];}
          {_args = ["QT_QPA_PLATFORM" "wayland;xcb"];}
          {_args = ["CLUTTER_BACKEND" "wayland"];}
          {_args = ["ANKI_WAYLAND" "1"];}
          {_args = ["MOZ_ENABLE_WAYLAND" "1"];}
          {_args = ["XDG_CURRENT_DESKTOP" "Hyprland"];}
          {_args = ["XDG_SESSION_TYPE" "wayland"];}
          {_args = ["XDG_SESSION_DESKTOP" "Hyprland"];}
        ];

        on = {
          _args = [
            "hyprland.start"
            (lua ''
              function()
                hl.exec_cmd(${builtins.toJSON "hyprctl setcursor ${config.home.pointerCursor.name} ${toString config.home.pointerCursor.size}"})
                hl.exec_cmd(${builtins.toJSON "${pkgs.hyprpolkitagent}/bin/hyprpolkitagent"})
                hl.exec_cmd("systemctl --user start transmission-daemon.service")
                hl.exec_cmd(${builtins.toJSON "${applyHyprglassSettings}"})
              end
            '')
          ];
        };

        config = {
          misc = {
            disable_hyprland_logo = true;
            disable_splash_rendering = true;
            force_default_wallpaper = 0;
            enable_anr_dialog = false;
            anr_missed_pings = 20;
            # Solid black background before wallpaper loads - avoids the
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
            enable_stdout_logs = false;
            disable_time = true;
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
            hide_on_key_press = true;
            inactive_timeout = 5;
          };

          general = {
            gaps_in = 5;
            gaps_out = 10;
            border_size = 2;
            layout = "dwindle";
            # col.active_border and col.inactive_border are set dynamically by dms.colors.
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
              contrast = 1.0;
              xray = true;
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
          };
        };

        curve = {
          _args = [
            "myBezier"
            {
              type = "bezier";
              points = [
                [0.05 0.9]
                [0.1 1.05]
              ];
            }
          ];
        };

        animation = [
          {
            leaf = "windows";
            enabled = true;
            speed = 7;
            bezier = "myBezier";
          }
          {
            leaf = "windowsOut";
            enabled = true;
            speed = 7;
            bezier = "default";
            style = "popin 80%";
          }
          {
            leaf = "border";
            enabled = true;
            speed = 10;
            bezier = "default";
          }
          {
            leaf = "fade";
            enabled = true;
            speed = 7;
            bezier = "default";
          }
          {
            leaf = "workspaces";
            enabled = true;
            speed = 6;
            bezier = "default";
          }
        ];

        bind =
          [
            # --- System & Apps ---
            (execBind (modKey "Return") "ghostty")
            (execBind (modKey "KP_Enter") "ghostty")
            (execBind (modKey "b") "brave")
            (bind (modKey "x") (lua "hl.dsp.window.close()"))
            (execBind (modKey "SHIFT + x") "hypr-quit-active")
            (execBind (modKey "m") "ghostty -e spotify_player")
            (execBind (modKey "e") "ghostty -e yazi")
            (bind (modKey "v") (lua ''hl.dsp.window.float({ action = "toggle" })''))
            (bind (modKey "f") (fullscreen "fullscreen"))
            (bind (modKey "SHIFT + f") (fullscreen "maximized"))
            (execBind (modKey "d") "dms ipc call spotlight toggle")
            (execBind (modKey "t") "dms ipc call notepad toggle")
            (execBind (modKey "SHIFT + v") "dms ipc call clipboard toggle")
            (bind (modKey "p") (lua "hl.dsp.window.pseudo()"))
            (bind (modKey "backslash") (lua ''hl.dsp.layout("togglesplit")''))
            (bind (modKey "g") (lua "hl.dsp.group.toggle()"))
            (bind (modKey "Tab") (lua "hl.dsp.group.next()"))

            # --- Navigation ---
            (bind (modKey "h") navL)
            (bind (modKey "l") navR)
            (bind (modKey "k") (focusDirection "up"))
            (bind (modKey "j") (focusDirection "down"))
            (bind (modKey "Left") (focusMonitor "l"))
            (bind (modKey "Right") (focusMonitor "r"))
            (bind (modKey "Up") (focusMonitor "u"))
            (bind (modKey "Down") (focusMonitor "d"))

            # --- Window Movement ---
            (bind (modKey "SHIFT + h") (moveWindowDirection "left"))
            (bind (modKey "SHIFT + l") (moveWindowDirection "right"))
            (bind (modKey "SHIFT + k") (moveWindowDirection "up"))
            (bind (modKey "SHIFT + j") (moveWindowDirection "down"))
            (bind (modKey "SHIFT + Left") (moveWindowMonitor "l"))
            (bind (modKey "SHIFT + Right") (moveWindowMonitor "r"))
          ]
          ++ workspaceBinds
          ++ [
            # --- Special Workspaces ---
            (bind (modKey "grave") (toggleSpecialWorkspace "music"))
            (bind (modKey "SHIFT + grave") (moveToWorkspace "special:music" true))
            (bind (modKey "CTRL + grave") (moveToWorkspace "special:music" false))

            # --- Screenshots (image to clipboard) ---
            (execBind "Print" "dms screenshot region --dir ~/pictures/screenshots")
            (execBind "CONTROL + Print" "dms screenshot window --dir ~/pictures/screenshots")
            (execBind "ALT + Print" "dms screenshot full --dir ~/pictures/screenshots")

            # --- Screenshots (file path to clipboard) ---
            (execBind "SHIFT + Print" "screenshot-path-copy region")
            (execBind "CONTROL + SHIFT + Print" "screenshot-path-copy window")
            (execBind "ALT + SHIFT + Print" "screenshot-path-copy full")

            # --- Screen Recording ---
            (execBind (modKey "r") "gsr-record region")
            (execBind (modKey "SHIFT + r") "gsr-record region --no-audio")
            (execBind (modKey "ALT + r") "gsr-record fullscreen")
            (execBind (modKey "ALT + SHIFT + r") "gsr-record fullscreen --no-audio")
            (execBind (modKey "CTRL + r") "gsr-record window")
            (execBind (modKey "CTRL + SHIFT + r") "gsr-record window --no-audio")

            # --- DMS IPC Controls ---
            (execBind (modKey "n") "dms ipc call notifications toggle")
            (execBind (modKey "SHIFT + n") "dms ipc call notifications clearAll; dms ipc call notifications clearHistory")
            (execBind (modKey "BackSpace") "dms ipc call notifications dismissAllPopups")
            (execBind (modKey "o") "dms ipc call hypr toggleOverview")
            (execBind (modKey "Escape") "dms ipc call lock lock")
            (execBind (modKey "s") "dms ipc call settings toggle")
            (execBind (modKey "q") "dms ipc call powermenu toggle")
            (execBind (modKey "w") "skwd wall toggle")
            (execBind (modKey "SHIFT + w") "dms ipc call dash toggle wallpaper")
            (execBind (modKey "SHIFT + o") "dms ipc call dash toggle overview")
            (execBind (modKey "SHIFT + m") "dms ipc call dash toggle media")
            (execBind (modKey "ALT + w") "dms ipc call dash toggle weather")
          ]
          ++ mediaBinds
          ++ repeatBinds
          ++ mouseBinds;

        window_rule = [
          {
            name = "media-opaque";
            match.class = "^(mpv|vlc|imv|feh)$";
            opacity = "1.0 override";
          }
          {
            name = "pip-opaque";
            match.title = "^(Picture-in-Picture)$";
            opacity = "1.0 override";
          }
          # Keep real fullscreen windows at full brightness even when unfocused.
          {
            name = "fullscreen-internal-no-dim";
            match.fullscreen_state_internal = 2;
            no_dim = true;
          }
          {
            name = "fullscreen-client-no-dim";
            match.fullscreen_state_internal = 3;
            no_dim = true;
          }
          # Keep Vesktop fully opaque at compositor level; transparent UI
          # comes from Vesktop's native RGBA setting to preserve text opacity.
          {
            name = "vesktop-opaque";
            match.class = "^(vesktop)$";
            opacity = "1.0 override";
          }
          # Center credential/auth dialogs so they don't spawn between monitors
          {
            name = "auth-dialogs";
            match.class = "^(pinentry|pinentry-gtk-2|pinentry-gnome3|ssh-askpass|git-askpass)$";
            float = true;
            center = true;
            size = "400 200";
          }
          {
            name = "pearpass-no-blur";
            match.class = "^(pear-runtime)$";
            no_blur = true;
          }
        ];

        layer_rule = [
          {
            name = "dms-blur";
            match.namespace = "^dms:(${dmsBlurNamespaces})$";
            blur = true;
          }
          {
            name = "dms-ignore-alpha";
            match.namespace = "^dms:(${dmsBlurNamespaces})$";
            ignore_alpha = 0.2;
          }
          {
            name = "wallpaper-selector-blur";
            match.namespace = "^wallpaper-selector-parallel$";
            blur = true;
          }
          {
            name = "wallpaper-selector-ignore-alpha";
            match.namespace = "^wallpaper-selector-parallel$";
            ignore_alpha = 0.2;
          }
        ];
      };

      extraConfig = ''
        local hm_xdg_config_home = os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")
        package.path = hm_xdg_config_home .. "/hypr/?.lua;" .. hm_xdg_config_home .. "/hypr/?/init.lua;" .. package.path

        local function require_optional(module)
          local ok, err = pcall(require, module)
          if not ok then
            print("failed to load " .. module .. ": " .. tostring(err))
          end
        end

        hl.exec_cmd(${builtins.toJSON "${applyHyprglassSettings}"})

        require_optional("dms.colors")
        require_optional("dms.cursor")
        require_optional("dms.layout")
        require_optional("dms.outputs")
        require_optional("dms.binds")
        require_optional("dms.binds-user")
        require_optional("dms.windowrules")
      '';
    };
  };
}
