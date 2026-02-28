{
  config,
  pkgs,
  ...
}: {
  programs.zellij = {
    enable = true;
    enableBashIntegration = false;
    settings = {
      default_shell = "bash";
    };
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
      if [[ $# -eq 1 ]]; then
          selected_path=$1
      else
          selected_path=$(find ~/repositories ~/system_manifest -mindepth 1 -maxdepth 2 -type d | fzf)
      fi

      if [[ -z $selected_path ]]; then
          exit 0
      fi

      selected_name=$(basename "$selected_path" | tr . _)

      if [[ -z $ZELLIJ ]]; then
          cd "$selected_path"
          zellij attach -c "$selected_name"
      else
          zellij action new-tab -l dev -c "$selected_path" -n "$selected_name"
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

        tab name="opencode" {
            pane command="opencode"
        }
    }
  '';

  home.shellAliases = {
    zellij-sessionizer = "zs ~/repositories";
  };
}
