{lib, ...}: {
  programs.dank-material-shell.settings = {
    displayProfileAutoSelect = lib.mkForce true;
  };

  xdg.configFile."hypr/dms/outputs.lua".text = ''
    -- Laptop displays are hardware-specific; let Hyprland auto-select the panel.
    hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "1" })
  '';
}
