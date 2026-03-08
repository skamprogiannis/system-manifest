{pkgs, ...}: {
  # Systemd user service for gnome-keyring-daemon — needed because Hyprland
  # doesn't process XDG autostart entries (only GNOME session manager does).
  # PAM still handles auto-unlock with the login password.
  services.gnome-keyring = {
    enable = true;
    components = ["secrets" "pkcs11"];
  };

  home.packages = with pkgs; [
    seahorse
  ];
}
