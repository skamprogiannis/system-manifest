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
      font-size = 13;
      background-opacity = 0.85;

      # Cursor and shell settings
      cursor-style = "block";
      cursor-style-blink = true;
      shell-integration-features = "no-cursor";

      # Fix for Zellij backspace issue (disabling modern protocol for stability)
      # Using standard TERM for best compatibility
      env = [
        "TERM=xterm-256color"
      ];

      # Mapping to standard Enter keycode for better application compatibility
      keybind = [
        "kp_enter=text:\\r"
      ];
    };
  };
}
