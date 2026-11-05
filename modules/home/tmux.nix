{...}: {
  programs.tmux = {
    enable = true;
    shortcut = "b";
    terminal = "tmux-256color";
    sensibleOnTop = false;
    extraConfig = ''
      set -as terminal-features ',xterm-ghostty:RGB'
      # Forward pane bells so Ghostty can request Hyprland attention.
      set -g bell-action any
    '';
  };
}
