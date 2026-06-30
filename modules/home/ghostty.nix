{
  pkgs,
  inputs,
  ...
}: let
  glass = import ./glass.nix;
in {
  programs.ghostty = {
    enable = true;
    package = inputs.ghostty.packages.${pkgs.stdenv.hostPlatform.system}.ghostty;
    enableBashIntegration = false;
    settings = {
      theme = "Catppuccin Mocha";
      background-opacity = glass.ghostty.backgroundOpacity;
      background-opacity-cells = true;
      background-blur = glass.ghostty.backgroundBlur;
      background = "000000";
      selection-foreground = "cdd6f4";
      selection-background = "313244";
      font-family = "JetBrainsMono Nerd Font";
      font-size = 11;

      # Cursor and shell settings
      # Keep translucent glyph edges stable on the glass background.
      alpha-blending = "linear-corrected";
      # Boost contrast ratio threshold so text stays readable on bright wallpapers.
      minimum-contrast = glass.ghostty.minimumContrast;
      # Codex uses BEL for "needs input"; attention maps it to Hyprland urgency.
      bell-features = "no-system,no-audio,attention,title,no-border";
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
