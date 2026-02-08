{
  config,
  pkgs,
  ...
}: {
  home.username = "stefan";
  home.homeDirectory = "/home/stefan";

  # --- PACKAGES ---
  home.packages = with pkgs; [
    # GUI
    brave
    discord
    obsidian
    protonmail-bridge
    spotify

    # CLI / Tools
    fastfetch
    btop
    ripgrep
    fd
    wl-clipboard
    cliphist
    curl
    gh
    opencode
    alejandra
    nodejs_22
    zellij

    # Hyprland Ecosystem
    waybar # Status bar
    wofi # App launcher
    dunst # Notifications
    hyprpaper # Wallpaper
  ];

  # --- GHOSTTY CONFIG ---
  programs.ghostty = {
    enable = true;
    enableBashIntegration = true;
    settings = {
      theme = "Dracula";
      font-family = "JetBrainsMono Nerd Font";
      font-size = 13;
      background-opacity = 0.85;

      # Cyberpunk tweaks
      cursor-style = "block";
      cursor-style-blink = true;
      shell-integration-features = "no-cursor";
    };
  };

  # --- GIT CONFIG ---
  programs.git = {
    enable = true;
    userName = "Stefan";
    userEmail = "boot.stefan.os@proton.me";
    extraConfig = {
      core = {
        editor = "nvim";
      };
      credential = {
        helper = "${pkgs.gh}/bin/gh auth git-credential";
      };
    };
  };

  # --- GNOME KEYBINDINGS ---
  dconf.settings = {
    "org/gnome/settings-daemon/plugins/media-keys" = {
      custom-keybindings = [
        "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/"
      ];
    };
    "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0" = {
      binding = "<Super>Return";
      command = "ghostty";
      name = "Ghostty";
    };
  };

  # --- PEARPASS WRAPPER & NATIVE MESSAGING ---
  home.file = let
    pearpassExtensionId = "pdeffakfmcdnjjafophphgmddmigpejh";
    pearpassNativeHostName = "com.tetherto.pearpass";

    pearpassApp = pkgs.appimageTools.wrapType2 {
      pname = "pearpass-desktop";
      version = "1.3.0";
      src = pkgs.fetchurl {
        url = "https://github.com/tetherto/pearpass-app-desktop/releases/download/v1.3.0/PearPass-Desktop-Linux-x64-v1.3.0.AppImage";
        sha256 = "1fl5g4jb7k6y5j50cm8dfdib2kw31g4c0akz4svkbwf4szwlm1dn";
      };
    };

    pearpassNativeWrapper = pkgs.writeShellScript "pearpass-native" ''
      exec ${pearpassApp}/bin/pearpass-desktop "$@"
    '';

    pearpassManifest = pkgs.writeText "pearpass-manifest.json" (builtins.toJSON {
      name = pearpassNativeHostName;
      description = "PearPass Native Messaging Host";
      path = "${pearpassNativeWrapper}";
      type = "stdio";
      allowed_origins = [
        "chrome-extension://${pearpassExtensionId}/"
      ];
    });
  in {
    # Opencode Config
    ".config/opencode/opencode.json".text = ''
      {
        "$schema": "https://opencode.ai/config.json",
        "plugin": ["opencode-gemini-auth@latest"],
        "mcpServers": {
          "context7": {
            "command": "npx",
            "args": ["-y", "@upstash/context7-mcp"]
          }
        }
      }
    '';

    ".local/share/applications/pearpass.desktop".source = "${pearpassApp}/share/applications/pearpass-desktop.desktop";

    ".config/google-chrome/NativeMessagingHosts/${pearpassNativeHostName}.json".source = pearpassManifest;
    ".config/chromium/NativeMessagingHosts/${pearpassNativeHostName}.json".source = pearpassManifest;
    ".config/BraveSoftware/Brave-Browser/NativeMessagingHosts/${pearpassNativeHostName}.json".source = pearpassManifest;
  };

  home.sessionVariables = {
    EDITOR = "nvim";
  };

  # --- NEOVIM CONFIG ---
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;

    plugins = with pkgs.vimPlugins; [
      nvim-treesitter.withAllGrammars # Better syntax highlighting
      telescope-nvim # Fuzzy finder
      opencode-nvim # vscode style sidebar for opencode
    ];
  };

  # --- HYPRLAND CONFIG (Cyberpunk Vibes) ---
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
        drop_shadow = true;
        shadow_range = 4;
        shadow_render_power = 3;
        "col.shadow" = "rgba(1a1a1aee)";
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

  # Let Home Manager manage itself
  programs.home-manager.enable = true;
  home.stateVersion = "24.11";
}
