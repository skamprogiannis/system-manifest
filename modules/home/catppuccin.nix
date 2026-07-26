{...}: {
  # Share one static palette while leaving Matugen-owned integrations alone.
  catppuccin = {
    enable = true;
    autoEnable = false;
    flavor = "mocha";
    accent = "blue";

    bat.enable = true;
    brave.enable = true;
    ghostty.enable = true;
    zellij.enable = true;
  };
}
