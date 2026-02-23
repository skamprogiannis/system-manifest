{
  config,
  pkgs,
  ...
}: {
  programs.ghostty = {
    enable = true;
    enableBashIntegration = true;
    settings = {
      theme = "Dracula";
      font-family = "JetBrainsMono Nerd Font";
      font-size = 11;
      background-opacity = 0.85;

      # Cursor and shell settings
      cursor-style = "block";
      cursor-style-blink = true;
      shell-integration-features = "no-cursor";

      # Mapping to standard Enter and Backspace for better application compatibility
      keybind = [
        "kp_enter=text:\\r"
        "backspace=text:\\x7f"
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
