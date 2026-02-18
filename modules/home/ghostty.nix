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

      # Cyberpunk tweaks
      cursor-style = "block";
      cursor-style-blink = true;
      shell-integration-features = "no-cursor";

      # Fix Numpad Enter
      # Mapping to standard Enter keycode for better application compatibility
      keybind = [
        "kp_enter=text:\\r"
        # Brave Harmony: Jump to specific tabs
        "ctrl+1=goto_tab:1"
        "ctrl+2=goto_tab:2"
        "ctrl+3=goto_tab:3"
        "ctrl+4=goto_tab:4"
        "ctrl+5=goto_tab:5"
        "ctrl+6=goto_tab:6"
        "ctrl+7=goto_tab:7"
        "ctrl+8=goto_tab:8"
        "ctrl+9=last_tab"
      ];
    };
  };
}
