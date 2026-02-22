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
      terminal-features = "-kitty-keyboard";

      # Mapping to standard Enter keycode for better application compatibility
      keybind = [
        "kp_enter=text:\\r"
      ];
    };
  };
}
