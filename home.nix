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

    # CLI / Tools
    fastfetch
    btop
    ripgrep
    fd
    wl-clipboard
    curl
    gh
    opencode
    alejandra

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
    settings = {
      user = {
        name = "Stefan";
        email = "boot.stefan.os@proton.me";
      };
    };
  };

  # --- OPENCODE CONFIG ---
  home.file.".config/opencode/opencode.json".text = ''
    {
      "$schema": "https://opencode.ai/config.json",
      "plugin": ["opencode-gemini-auth@latest"]
    }
  '';

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
      exec-once = ["waybar" "dunst" "hyprpaper"];

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
        "$mod, Q, exec, $terminal"
        "$mod, C, killactive,"
        "$mod, M, exit,"
        "$mod, E, exec, nautilus"
        "$mod, V, togglefloating,"
        "$mod, R, exec, $menu"
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
