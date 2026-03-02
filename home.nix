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
    ./modules/home/dms.nix
    ./modules/home/pearpass.nix
    ./modules/home/xdg.nix
    ./modules/home/brave.nix
    ./modules/home/firefox.nix
    ./modules/home/theme.nix
    ./modules/home/obsidian.nix
    ./modules/home/zellij.nix
    ./modules/home/scripts.nix
    ./modules/home/wallpaper.nix
    ./modules/home/cursors.nix
  ];

  # --- PACKAGES ---
  home.packages = with pkgs; [
    # GUI
    mpvpaper
    discord
    mailspring
    obsidian
    protonvpn-gui
    swww

    # CLI / Tools
    alejandra
    curl
    fastfetch
    fd
    ffmpegthumbnailer
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
    transmission_4
    wget
    wl-clipboard
    zathura

    # Disk Utilities
    dosfstools
    e2fsprogs
    parted

    # Fonts
    nerd-fonts.jetbrains-mono
  ];

  fonts.fontconfig.enable = true;

  home.file.".inputrc".text = ''
    set editing-mode vi
  '';

  home.file."${config.xdg.configHome}/spotify-player/app.toml".text = ''
    client_port = 8081
    login_redirect_uri = "http://127.0.0.1:8989/login"
    enable_streaming = "Always"

    [device]
    name = "nixos-desktop"
    device_type = "computer"
    volume = 90
    bitrate = 320
    audio_cache = true
    normalization = false
  '';

  programs.spotify-player = {
    enable = true;
    package = inputs.spotify-player.defaultPackage.${pkgs.stdenv.hostPlatform.system};
  };

  # Systemd service for spotify-player daemon
  systemd.user.services.spotify-player = {
    Unit = {
      Description = "Spotify Player Daemon";
      After = ["network-online.target"];
      Wants = ["network-online.target"];
      StartLimitIntervalSec = 300;
      StartLimitBurst = 3;
    };
    Service = {
      ExecStartPre = "${pkgs.util-linux}/bin/fuser -k 8081/tcp || true";
      ExecStart = "${inputs.spotify-player.defaultPackage.${pkgs.stdenv.hostPlatform.system}}/bin/spotify_player --daemon";
      Restart = "on-failure";
      RestartSec = "30s";
    };
    Install = {
      WantedBy = ["default.target"];
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
    # Input sources for GNOME
    "org/gnome/desktop/input-sources" = {
      sources = [(lib.hm.gvariant.mkTuple ["xkb" "us+altgr-intl"]) (lib.hm.gvariant.mkTuple ["xkb" "gr"])];
    };
    "org/gnome/desktop/wm/keybindings" = {
      switch-input-source = ["<Super>space"];
      switch-input-source-backward = ["<Shift><Super>space"];
      close = ["<Super>x"];
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
    "org/gnome/desktop/interface" = {
    };
  };

  programs.home-manager.enable = true;
  programs.bash = {
    enable = true;
    enableCompletion = true;
    initExtra = ''
      set -o vi
      # Arrow keys for history search in Vi mode
      bind '"\e[A": history-search-backward'
      bind '"\e[B": history-search-forward'
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
    shellWrapperName = "y";
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
  xdg.desktopEntries.btop = {
    name = "btop";
    exec = "ghostty -e btop";
    noDisplay = true;
  };

  xdg.mimeApps = {
    enable = true;
    associations.added = {
      "x-scheme-handler/magnet" = ["tremc.desktop"];
      "application/x-bittorrent" = ["tremc.desktop"];
    };
    defaultApplications = {
      "x-scheme-handler/magnet" = ["tremc.desktop"];
      "application/x-bittorrent" = ["tremc.desktop"];
      "image/png" = ["org.gnome.Loupe.desktop"];
      "image/jpeg" = ["org.gnome.Loupe.desktop"];
      "image/gif" = ["org.gnome.Loupe.desktop"];
      "image/webp" = ["org.gnome.Loupe.desktop"];
      "image/bmp" = ["org.gnome.Loupe.desktop"];
      "image/tiff" = ["org.gnome.Loupe.desktop"];
      "image/svg+xml" = ["org.gnome.Loupe.desktop"];
      "application/pdf" = ["org.pwmt.zathura.desktop"];
      "text/plain" = ["org.gnome.TextEditor.desktop"];
    };
  };
}


