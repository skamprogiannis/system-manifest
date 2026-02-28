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
    enableBashIntegration = false;
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
          default_layout = "dev";
        }
      );
    extraConfig = ''
      keybinds {
          unbind "Ctrl p" "Ctrl t" "Ctrl n" "Ctrl s" "Ctrl o" "Ctrl q" "Ctrl g" "Ctrl r" "Ctrl d" "Ctrl h" "Ctrl j" "Ctrl k" "Ctrl l" "Ctrl b" "Alt i" "Alt s"

          locked {
            bind "Alt g" { SwitchToMode "Normal"; }
          }

          shared_except "locked" {
            // --- INVERSE LAYOUT ---
            // Modes (Alt)
            bind "Alt p" { SwitchToMode "Pane"; }
            bind "Alt t" { SwitchToMode "Tab"; }
            bind "Alt r" { SwitchToMode "Resize"; }
            bind "Alt s" { SwitchToMode "Scroll"; }
            bind "Alt o" { SwitchToMode "Session"; }
            bind "Alt g" { SwitchToMode "Locked"; }
            bind "Alt q" { Quit; }

            // Navigation (Alt focus)
            bind "Alt h" { MoveFocusOrTab "Left"; }
            bind "Alt l" { MoveFocusOrTab "Right"; }
            bind "Alt j" { MoveFocus "Down"; }
            bind "Alt k" { MoveFocus "Up"; }
            bind "Alt Left" { MoveFocusOrTab "Left"; }
            bind "Alt Right" { MoveFocusOrTab "Right"; }
            bind "Alt Down" { MoveFocus "Down"; }
            bind "Alt Up" { MoveFocus "Up"; }

            // Fast Tab Navigation
            bind "Alt H" { GoToPreviousTab; }
            bind "Alt L" { GoToNextTab; }

            // Global Actions (Alt)
            bind "Alt n" { NewTab; }
            bind "Alt f" { ToggleFloatingPanes; }
            bind "Alt x" { CloseFocus; }
            bind "Alt d" { Detach; }

            // Tab Switching
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
            bind "Alt Tab" { GoToNextTab; }
            bind "Alt Shift Tab" { GoToPreviousTab; }
            
          }
          
          move {
            bind "h" { MovePane "Left"; }
            bind "l" { MovePane "Right"; }
            bind "j" { MovePane "Down"; }
            bind "k" { MovePane "Up"; }
          }

          tab {
            bind "h" "k" "Left" "Up" { GoToPreviousTab; }
            bind "l" "j" "Right" "Down" { GoToNextTab; }
            bind "Alt h" "Alt Left" { MoveTab "Left"; }
            bind "Alt l" "Alt Right" { MoveTab "Right"; }
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
        if zellij list-sessions | grep -q "^$session_name"; then
            zellij attach "$session_name"
        else
            zellij attach -c "$session_name"
        fi
      else
        zellij action new-tab -l dev -c "$selected_path" -n "$session_name"
      fi
    '')
  ];

  xdg.configFile."zellij/layouts/dev.kdl".text = ''
    layout {
        default_tab_template {
            pane size=1 borderless=true {
                plugin location="zellij:tab-bar"
            }
            children
            pane size=1 borderless=true {
                plugin location="zellij:compact-bar"
            }
        }
        
        tab name="vim" focus=true {
            pane split_direction="horizontal" {
                pane size="80%" command="nvim" focus=true
                pane size="20%"
            }
        }
    }
  '';

  home.shellAliases = {
    zellij-sessionizer = "zs ~/repositories";
  };
}
