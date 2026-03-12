# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).
{
  config,
  pkgs,
  inputs,
  lib,
  ...
}: {
  imports = [
    # hardware-configuration.nix is imported by the specific host
  ];

  # Track configuration revision
  system.configurationRevision = inputs.self.rev or inputs.self.dirtyRev or null;

  # Enable experimental features and binary caches
  nix.settings = {
    experimental-features = ["nix-command" "flakes"];
    substituters = [
      "https://cache.nixos.org"
      "https://hyprland.cachix.org"
      "https://nix-community.cachix.org"
      "https://ghostty.cachix.org"
    ];
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "ghostty.cachix.org-1:QB389yTa6gTyneehvqG58y0WnHjQOqgnA+wBnpWWxns="
    ];
  };

  # Use LTS kernel for better stability
  boot.kernelPackages = pkgs.linuxPackages;

  # Networking
  # HostName is defined in host specific config
  networking.networkmanager.enable = true;
  networking.nameservers = [ "9.9.9.9" "149.112.112.112" ];

  # Time & Locales
  time.timeZone = "Europe/Athens";
  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "el_GR.UTF-8";
    LC_IDENTIFICATION = "el_GR.UTF-8";
    LC_MEASUREMENT = "el_GR.UTF-8";
    LC_MONETARY = "el_GR.UTF-8";
    LC_NAME = "el_GR.UTF-8";
    LC_PAPER = "el_GR.UTF-8";
    LC_TELEPHONE = "el_GR.UTF-8";
    LC_NUMERIC = "en_GB.UTF-8";
    LC_TIME = "en_GB.UTF-8";
  };

  # Enable OpenGL
  hardware.graphics.enable = true;

  # Enable the X11 windowing system
  services.xserver.enable = true;
  services.xserver.excludePackages = [pkgs.xterm];
  services.xserver.desktopManager.xterm.enable = false;

  # Enable nix-ld for Opencode/dynamic binaries
  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [
    stdenv.cc.cc.lib
    zlib
    openssl
  ];

  # Allow the user to rebuild the system without a password
  security.sudo.extraRules = [
    {
      users = ["stefan"];
      commands = [
        {
          command = "/run/current-system/sw/bin/nixos-rebuild";
          options = ["NOPASSWD"];
        }
      ];
    }
  ];

  # Allow the user to manage NetworkManager without a password via Polkit
  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if (subject.user == "stefan") {
        if (action.id == "org.freedesktop.NetworkManager.network-control" ||
            action.id == "org.freedesktop.NetworkManager.settings.modify.system") {
          return polkit.Result.YES;
        }
      }
    });
  '';

  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "us,gr";
    variant = "altgr-intl,simple";
    options = "grp:win_space_toggle";
  };

  # Enable CUPS to print documents
  services.printing.enable = false;

  services.gnome.gnome-keyring.enable = true;
  security.pam.services.login.enableGnomeKeyring = true;
  security.pam.services.gdm.enableGnomeKeyring = true;
  security.pam.services.gdm-password.enableGnomeKeyring = true;
  security.pam.services.greetd.enableGnomeKeyring = true;

  # Enable sound with pipewire
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # Prevent annoying 90s hang on shutdown if a service fails to stop
  systemd.settings.Manager.DefaultTimeoutStopSec = "10s";

  # Define a user account. Don't forget to set a password with ‘passwd’
  users.users.stefan = {
    isNormalUser = true;
    description = "Stefan";
    extraGroups = ["networkmanager" "wheel"];
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;
  nixpkgs.config.permittedInsecurePackages = [
    "libsoup-2.74.3"
    "openssl-1.1.1w"
  ];

  # Required for Home Manager XDG portals
  environment.pathsToLink = ["/share/applications" "/share/xdg-desktop-portal"];

  # List packages installed in system profile.
  environment.systemPackages = with pkgs; [
    wget
    git
    inotify-tools
    # GStreamer plugins for video playback and subtitles
    gst_all_1.gstreamer
    gst_all_1.gst-plugins-base
    gst_all_1.gst-plugins-good
    gst_all_1.gst-plugins-bad
    gst_all_1.gst-plugins-ugly
    gst_all_1.gst-libav
  ];

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "25.11"; # Did you read the comment?
}
