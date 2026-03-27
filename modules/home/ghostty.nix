{
  config,
  pkgs,
  inputs,
  ...
}: {
  programs.ghostty = {
    enable = true;
    package = inputs.ghostty.packages.${pkgs.stdenv.hostPlatform.system}.ghostty;
    enableBashIntegration = false;
    settings = {
      theme = "Catppuccin Mocha";
      background-opacity = 0.40;
      background = "000000";
      font-family = "JetBrainsMono Nerd Font";
      font-size = 11;

      # Cursor and shell settings
      minimum-contrast = 2.0; 
      cursor-style = "block";
      cursor-style-blink = false;
      shell-integration-features = "no-cursor";

      # Mapping to standard Enter and Backspace for better application compatibility
      keybind = [
        "kp_enter=text:\\r"
        "backspace=text:\\x7f"

        # Unbind Ghostty-intercepted shortcuts (let Zellij/apps handle them)
        "ctrl+shift+t=unbind"
        "ctrl+shift+w=unbind"
        "ctrl+shift+e=unbind"
        "ctrl+shift+o=unbind"
        "ctrl+shift+n=unbind"
        "ctrl+shift+i=unbind"
        "ctrl+shift+j=unbind"
        "ctrl+shift+k=unbind"
        "ctrl+shift+l=unbind"

      ];
    };
  };
}
