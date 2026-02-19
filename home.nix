{
  config,
  pkgs,
  inputs,
  lib,
  ...
}: {
  home.username = "stefan";
  home.homeDirectory = "/home/stefan";

  imports = [
    ./modules/home/git.nix
    ./modules/home/ghostty.nix
    ./modules/home/neovim.nix
    ./modules/home/opencode.nix
    ./modules/home/hyprland.nix
    ./modules/home/pearpass.nix
    ./modules/home/xdg.nix
    ./modules/home/brave.nix
    ./modules/home/firefox.nix
    ./modules/home/theme.nix
    ./modules/home/obsidian.nix
  ];

  # --- PACKAGES ---
  home.packages = with pkgs; [
    # GUI
    discord
    evolution
    geary
    gnome-online-accounts
    obsidian
    protonvpn-gui

    # CLI / Tools
    alejandra
    btop
    cliphist
    curl
    dig
    fastfetch
    fd
    tremc
    glow
    go
    jq
    nodejs_22
    opencode
    pacvim
    pandoc
    python3
    ripgrep
    ruff
    sops
    transmission_4
    wget
    wl-clipboard

    # Disk Utilities
    dosfstools
    e2fsprogs
    parted

    # Fonts
    nerd-fonts.jetbrains-mono
  ];

  fonts.fontconfig.enable = true;

  sops = {
    age.keyFile = "/home/stefan/.config/sops/age/keys.txt";
    defaultSopsFile = ./secrets/secrets.yaml;
    secrets.spotify_client_id = {};
    secrets.spotify_client_secret = {};

    templates."spotify-player-app-toml" = {
      path = "${config.xdg.configHome}/spotify-player/app.toml";
      content = ''
        client_id = "${config.sops.placeholder.spotify_client_id}"
        client_secret = "${config.sops.placeholder.spotify_client_secret}"
        client_port = 8899
        login_redirect_uri = "http://127.0.0.1:8899/callback"

        [device]
        name = "nixos-desktop"
        device_type = "computer"
        volume = 90
        bitrate = 320
        audio_cache = true
        normalization = false
      '';
    };
  };



  # Force sops-nix to start on login to ensure secrets are rendered
  systemd.user.services.sops-nix.Install.WantedBy = [ "graphical-session.target" ];

  programs.spotify-player = {
    enable = true;
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
    # Input sources for GNOME
    "org/gnome/desktop/input-sources" = {
      sources = [(lib.hm.gvariant.mkTuple ["xkb" "us+altgr-intl"]) (lib.hm.gvariant.mkTuple ["xkb" "gr"])];
    };
    "org/gnome/desktop/wm/keybindings" = {
      switch-input-source = ["<Super>space"];
      switch-input-source-backward = ["<Shift><Super>space"];
      close = ["<Super>q"];
    };
    "org/gnome/gnome-screenshot" = {
      auto-save-directory = "file:///home/stefan/pictures/screenshots";
    };
    "org/gnome/shell" = {
      last-screenshot-directory = "file:///home/stefan/pictures/screenshots";
    };
    "org/gnome/shell/screenshot" = {
      last-save-directory = "file:///home/stefan/pictures/screenshots";
    };
  };

  programs.home-manager.enable = true;
  programs.bash = {
    enable = true;
    enableCompletion = true;
    initExtra = ''
      set -o vi
    '';
  };
  home.stateVersion = "24.11";

  home.sessionPath = ["$HOME/.local/bin"];

  home.shellAliases = {
    cat = "bat";
    find = "fd";
    grep = "rg";
    pearpass-dev = "cd ~/repositories/pearpass-app-desktop && npx pear run -d .";
    tremc = "systemd-inhibit --why='Downloading torrents' --who='tremc' --what='sleep:idle' tremc";
  };

  programs.bat = {
    enable = true;
    config = {
      theme = "Dracula";
      italic-text = "always";
    };
  };

  programs.lazygit = {
    enable = true;
    enableBashIntegration = true;
  };

  programs.fzf = {
    enable = true;
    enableBashIntegration = true;
  };

  programs.yazi = {
    enable = true;
    enableBashIntegration = true;
  };

  programs.zoxide = {
    enable = true;
    enableBashIntegration = true;
  };

  programs.gh = {
    enable = true;
    settings = {
      git_protocol = "ssh";
      prompt = "enabled";
    };
  };

  programs.zellij = {
    enable = true;
    enableBashIntegration = true;
  };

  # Systemd service for transmission-daemon
  systemd.user.services.transmission-daemon = {
    Unit = {
      Description = "Transmission BitTorrent Daemon";
      After = [ "network.target" ];
    };
    Service = {
      ExecStart = "${pkgs.transmission_4}/bin/transmission-daemon -f --no-auth --config-dir %h/.config/fragments --port 9091 --rpc-bind-address 127.0.0.1 --allowed 127.0.0.1";
      Restart = "on-failure";
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };

  # Configure default applications
  xdg.mimeApps = {
    enable = true;
    associations.added = {
      "x-scheme-handler/magnet" = ["tremc.desktop"];
      "application/x-bittorrent" = ["tremc.desktop"];
    };
    defaultApplications = {
      "x-scheme-handler/magnet" = ["tremc.desktop"];
      "application/x-bittorrent" = ["tremc.desktop"];
    };
  };
}


