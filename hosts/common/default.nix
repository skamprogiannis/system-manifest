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

  # Enable experimental features natively
  nix.settings.experimental-features = ["nix-command" "flakes"];

  # Use LTS kernel for better stability
  boot.kernelPackages = pkgs.linuxPackages;

  # Networking
  # HostName is defined in host specific config
  networking.networkmanager.enable = true;

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
  services.xserver.excludePackages = [ pkgs.xterm ];
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
    variant = "altgr-intl,";
    options = "grp:win_space_toggle";
  };

  # Enable CUPS to print documents
  services.printing.enable = false;

  # Enable sound with pipewire
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # Enable GNOME Keyring for email clients and other apps
  services.gnome.gnome-keyring.enable = true;
  security.pam.services.login.enableGnomeKeyring = true;
  security.pam.services.greetd.enableGnomeKeyring = true;
  security.pam.services.gdm.enableGnomeKeyring = true;
  security.pam.services.gdm-password.enableGnomeKeyring = true;
  services.gnome.gnome-online-accounts.enable = false;
  services.gnome.rygel.enable = false;

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
