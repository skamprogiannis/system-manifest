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
    ./modules/home/hyprland.nix
    ./modules/home/dms.nix
    ./modules/home/pearpass.nix
    ./modules/home/xdg.nix
    ./modules/home/brave.nix
    ./modules/home/gh-copilot
    ./modules/home/firefox.nix
    ./modules/home/theme.nix
    ./modules/home/obsidian.nix
    ./modules/home/spotify.nix
    ./modules/home/zellij.nix
    ./modules/home/scripts.nix
    ./modules/home/wallpaper.nix
    ./modules/home/cursors.nix
    ./modules/home/vesktop.nix
    ./modules/home/keyring.nix
  ];

  # --- PACKAGES ---
  home.packages = with pkgs; [
    # GUI
    imv
    kooha
    mpv
    linux-wallpaperengine
    nautilus
    vesktop
    pkgs.mailspring
    obsidian
    protonvpn-gui

    # CLI / Tools
    alejandra
    curl
    fastfetch
    fd
    ffmpegthumbnailer
    gcr
    # Wrap copilot CLI so keytar.node can find libsecret at runtime
    (pkgs.symlinkJoin {
      name = "github-copilot-cli-wrapped";
      paths = [ pkgs.github-copilot-cli ];
      nativeBuildInputs = [ pkgs.makeWrapper ];
      postBuild = ''
        wrapProgram $out/bin/copilot \
          --prefix LD_LIBRARY_PATH : "${pkgs.lib.makeLibraryPath [
            pkgs.libsecret
            pkgs.glib
            pkgs.gcc-unwrapped.lib
          ]}"
      '';
    })
    glow
    go
    gopls
    jq
    libsecret
    nodejs_22
    nodePackages.typescript-language-server
    omnisharp-roslyn
    pacvim
    pandoc
    python3
    python3Packages.python-lsp-server
    ripgrep
    ruff
    rust-analyzer
    transmission_4
    tremc
    uv
    wget
    wl-clipboard
    # Disk Utilities
    dosfstools
    e2fsprogs
    ncdu
    parted

    # Fonts
    nerd-fonts.jetbrains-mono
  ];

  fonts.fontconfig.enable = true;

  home.file.".inputrc".text = ''
    set editing-mode vi
    set show-mode-in-prompt on
    set vi-ins-mode-string "\1\e[6 q\2"
    set vi-cmd-mode-string "\1\e[2 q\2"
  '';

  programs.home-manager.enable = true;

  # Prevent long shutdown delays for user services
  systemd.user.settings.Manager.DefaultTimeoutStopSec = "2s";

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

  programs.zathura = {
    enable = true;
    options.selection-clipboard = "clipboard";
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

  xdg.desktopEntries.btop = {
    name = "btop";
    exec = "ghostty -e btop";
    noDisplay = true;
  };

  xdg.desktopEntries."Mailspring" = {
    name = "Mailspring";
    comment = "The best email app for people and teams at work";
    genericName = "Mail Client";
    exec = "mailspring --password-store=gnome-libsecret %U";
    icon = "mailspring";
    categories = ["Network" "Email"];
    mimeType = ["x-scheme-handler/mailto" "x-scheme-handler/mailspring"];
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
      "image/png" = ["imv.desktop"];
      "image/jpeg" = ["imv.desktop"];
      "image/gif" = ["imv.desktop"];
      "image/webp" = ["imv.desktop"];
      "image/bmp" = ["imv.desktop"];
      "image/tiff" = ["imv.desktop"];
      "image/svg+xml" = ["imv.desktop"];
      "application/pdf" = ["org.pwmt.zathura.desktop"];
      "text/plain" = ["nvim-text.desktop"];
      "text/markdown" = ["nvim-text.desktop"];
      "text/css" = ["nvim-text.desktop"];
      "application/json" = ["nvim-text.desktop"];
      "application/x-shellscript" = ["nvim-text.desktop"];
    };
  };
}
