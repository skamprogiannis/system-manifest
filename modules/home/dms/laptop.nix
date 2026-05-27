{lib, ...}: {
  programs.dank-material-shell.settings = {
    displayProfileAutoSelect = lib.mkForce true;
  };

  xdg.configFile."hypr/dms/outputs.conf".text = ''
    # Laptop displays are hardware-specific; let Hyprland auto-select the panel.
    monitor = ,preferred,auto,1
  '';
}
