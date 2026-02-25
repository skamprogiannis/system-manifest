{
  config,
  pkgs,
  hostType ? "desktop",
  ...
}: let
  isPortable = hostType == "laptop" || hostType == "usb";
in {
  programs.zellij = {
    enable = true;
    enableBashIntegration = true;
    settings =
      {
        default_shell = "bash";
      }
      // (
        if isPortable
        then {
          pane_frames = false;
          simplified_ui = true;
          default_layout = "compact";
        }
        else {
          pane_frames = true;
        }
      );
    extraConfig = ''
      keybinds {
          shared_except "locked" {
            // Unbind default Ctrl binds to avoid UI clutter in the Inverse Layout
            unbind "Ctrl p" "Ctrl t" "Ctrl n" "Ctrl s" "Ctrl o" "Ctrl q" "Ctrl g" "Ctrl r" "Ctrl d"

            // --- INVERSE LAYOUT ---
            // Modes (Alt)
            bind "Alt p" { SwitchToMode "Pane"; }
            bind "Alt t" { SwitchToMode "Tab"; }
            bind "Alt r" { SwitchToMode "Resize"; }
            bind "Alt s" { SwitchToMode "Scroll"; }
            bind "Alt o" { SwitchToMode "Session"; }
            bind "Alt m" { SwitchToMode "Move"; }
            bind "Alt g" { SwitchToMode "Locked"; }
            bind "Alt q" { Quit; }

            // Navigation (Alt focus)
            bind "Alt h" { MoveFocus "Left"; }
            bind "Alt l" { MoveFocus "Right"; }
            bind "Alt j" { MoveFocus "Down"; }
            bind "Alt k" { MoveFocus "Up"; }

            // Global Actions (Ctrl)
            bind "Ctrl n" { NewPane "Down"; }
            bind "Ctrl f" { ToggleFloatingPanes; }
            bind "Ctrl x" { CloseFocus; }
            bind "Alt d" { Detach; }

            // Tab Switching (Both Ctrl and Alt)
            bind "Ctrl 1" { GoToTab 1; }
            bind "Alt 1" { GoToTab 1; }
            bind "Ctrl 2" { GoToTab 2; }
            bind "Alt 2" { GoToTab 2; }
            bind "Ctrl 3" { GoToTab 3; }
            bind "Alt 3" { GoToTab 3; }
            bind "Ctrl 4" { GoToTab 4; }
            bind "Alt 4" { GoToTab 4; }
            bind "Ctrl 5" { GoToTab 5; }
            bind "Alt 5" { GoToTab 5; }
            bind "Ctrl 6" { GoToTab 6; }
            bind "Alt 6" { GoToTab 6; }
            bind "Ctrl 7" { GoToTab 7; }
            bind "Alt 7" { GoToTab 7; }
            bind "Ctrl 8" { GoToTab 8; }
            bind "Alt 8" { GoToTab 8; }
            bind "Ctrl 9" { GoToTab 9; }
            bind "Alt 9" { GoToTab 9; }

            bind "Ctrl Tab" { GoToNextTab; }
            bind "Ctrl Shift Tab" { GoToPreviousTab; }
          }
      }
    '';
  };

  home.packages = [
    (pkgs.writeShellScriptBin "zs" ''
      paths=("''${@:-$HOME/repositories $HOME/system_manifest}")

      if command -v fd &> /dev/null; then
        selected_path=$(fd . ''${paths[@]} --min-depth 1 --max-depth 2 --type d 2>/dev/null | fzf)
      else
        selected_path=$(find ''${paths[@]} -mindepth 1 -maxdepth 2 -type d 2>/dev/null | fzf)
      fi

      if [[ -z "$selected_path" ]]; then
        exit 0
      fi

      session_name=$(basename "$selected_path" | tr . _)

      if [[ -z "$ZELLIJ" ]]; then
        cd "$selected_path"
        zellij attach "$session_name" -c
      else
        zellij action new-pane
        zellij action write-chars "cd $selected_path" && zellij action write 10
      fi
    '')
  ];

  home.shellAliases = {
    zellij-sessionizer = "zs ~/repositories";
  };
}
