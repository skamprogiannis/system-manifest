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
      background-opacity-cells = false;
      background = "000000";
      selection-foreground = "cdd6f4";
      selection-background = "313244";
      font-family = "JetBrainsMono Nerd Font";
      font-size = 11;

      # Cursor and shell settings
      # Keep translucent glyph edges stable on the glass background.
      alpha-blending = "linear-corrected";
      minimum-contrast = 1.0;
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
        "ctrl+enter=unbind"

      ];
    };
  };
}
