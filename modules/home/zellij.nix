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
      escape_timeout = 0;
    };
    extraConfig = ''
      keybinds {
          unbind "Ctrl p" "Ctrl t" "Ctrl n" "Ctrl s" "Ctrl o" "Ctrl q" "Ctrl g" "Ctrl r" "Ctrl d" "Ctrl h" "Ctrl j" "Ctrl k" "Ctrl l" "Ctrl b" "Alt i"

          locked {
            bind "Alt g" { SwitchToMode "Normal"; }
          }

          // Esc only exits modes back to Normal (not in Normal mode — pass through to apps)
          shared_except "locked" "normal" {
            bind "Esc" { SwitchToMode "Normal"; }
          }

          normal {
            // Esc is unbound so Vim, Copilot etc. receive it uninterrupted
            unbind "Esc"
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

            bind "Alt n" { NewTab; }
            bind "Alt f" { ToggleFloatingPanes; }
            bind "Alt x" { CloseFocus; }
            bind "Alt m" { SwitchToMode "Move"; }
            bind "Alt d" { Detach; }

            // Tab Switching
            bind "Alt 1" { GoToTab 1; }
            bind "Alt 2" { GoToTab 2; }
            bind "Alt 3" { GoToTab 3; }
            bind "Alt 4" { GoToTab 4; }
            bind "Alt 5" { GoToTab 5; }
            bind "Alt 6" { GoToTab 6; }
            bind "Alt 7" { GoToTab 7; }
            bind "Alt 8" { GoToTab 8; }
            bind "Alt 9" { GoToTab 9; }

            bind "Ctrl Tab" { GoToNextTab; }
            bind "Ctrl Shift Tab" { GoToPreviousTab; }
            bind "Alt Tab" { GoToNextTab; }
            bind "Alt Shift Tab" { GoToPreviousTab; }
            bind "Alt [" "Alt Shift Left" { MoveTab "Left"; }
            bind "Alt ]" "Alt Shift Right" { MoveTab "Right"; }

            // Stacking
            bind "Alt ," { TogglePaneEmbedOrEject; }
            bind "Alt ." { NewPane "stacked"; SwitchToMode "Normal"; }
          }
          
          move {
            bind "h" { MovePane "Left"; }
            bind "l" { MovePane "Right"; }
            bind "j" { MovePane "Down"; }
            bind "k" { MovePane "Up"; }
          }

          pane {
            bind "h" "Left" { MoveFocus "Left"; }
            bind "l" "Right" { MoveFocus "Right"; }
            bind "j" "Down" { MoveFocus "Down"; }
            bind "k" "Up" { MoveFocus "Up"; }
            bind "n" { NewPane; SwitchToMode "Normal"; }
            bind "d" { NewPane "Down"; SwitchToMode "Normal"; }
            bind "r" { NewPane "Right"; SwitchToMode "Normal"; }
            bind "s" { NewPane "stacked"; SwitchToMode "Normal"; }
            bind "p" { SwitchFocus; }
          }

          tab {
            bind "h" "k" "Left" "Up" { GoToPreviousTab; }
            bind "l" "j" "Right" "Down" { GoToNextTab; }
            bind "Alt h" "Alt Left" { MoveTab "Left"; }
            bind "Alt l" "Alt Right" { MoveTab "Right"; }
          }

          resize {
            bind "h" "Left" { Resize "Increase Left"; }
            bind "j" "Down" { Resize "Increase Down"; }
            bind "k" "Up" { Resize "Increase Up"; }
            bind "l" "Right" { Resize "Increase Right"; }
            bind "H" { Resize "Decrease Left"; }
            bind "J" { Resize "Decrease Down"; }
            bind "K" { Resize "Decrease Up"; }
            bind "L" { Resize "Decrease Right"; }
            bind "=" "+" { Resize "Increase"; }
            bind "-" { Resize "Decrease"; }
          }

          session {
            bind "d" { Detach; }
            bind "w" {
              LaunchOrFocusPlugin "session-manager" {
                floating true
                move_to_focused_tab true
              };
              SwitchToMode "Normal"
            }
            bind "c" {
              LaunchOrFocusPlugin "configuration" {
                floating true
                move_to_focused_tab true
              };
              SwitchToMode "Normal"
            }
            bind "p" {
              LaunchOrFocusPlugin "plugin-manager" {
                floating true
                move_to_focused_tab true
              };
              SwitchToMode "Normal"
            }
            bind "a" {
              LaunchOrFocusPlugin "zellij:about" {
                floating true
                move_to_focused_tab true
              };
              SwitchToMode "Normal"
            }
            bind "s" {
              LaunchOrFocusPlugin "zellij:share" {
                floating true
                move_to_focused_tab true
              };
              SwitchToMode "Normal"
            }
          }

          scroll {
            bind "j" "Down" { ScrollDown; }
            bind "k" "Up" { ScrollUp; }
            bind "Ctrl f" "PageDown" "l" "Right" { PageScrollDown; }
            bind "Ctrl b" "PageUp" "h" "Left" { PageScrollUp; }
            bind "Ctrl d" { HalfPageScrollDown; }
            bind "Ctrl u" { HalfPageScrollUp; }
            bind "s" { SwitchToMode "EnterSearch"; SearchInput 0; }
            bind "e" { EditScrollback; SwitchToMode "Normal"; }
          }

          search {
            bind "j" "Down" { ScrollDown; }
            bind "k" "Up" { ScrollUp; }
            bind "Ctrl f" "PageDown" "l" "Right" { PageScrollDown; }
            bind "Ctrl b" "PageUp" "h" "Left" { PageScrollUp; }
            bind "d" { HalfPageScrollDown; }
            bind "u" { HalfPageScrollUp; }
            bind "n" { Search "down"; }
            bind "p" { Search "up"; }
            bind "c" { SearchToggleOption "CaseSensitivity"; }
            bind "w" { SearchToggleOption "Wrap"; }
            bind "o" { SearchToggleOption "WholeWord"; }
          }

          entersearch {
            bind "Esc" { SwitchToMode "Scroll"; }
            bind "Enter" { SwitchToMode "Search"; }
          }
      }
    '';
  };

  home.packages = [
    (pkgs.writeShellScriptBin "zs" ''
      resolve_path() {
        local input="$1"
        
        if [[ -z "$input" ]]; then
          return 1
        fi
        
        if [[ -d "$input" ]]; then
          echo "$input"
          return 0
        fi
        
        if [[ -d ~/repositories/"$input" ]]; then
          echo ~/repositories/"$input"
          return 0
        fi
        
        if [[ -d ~/"$input" ]]; then
          echo ~/"$input"
          return 0
        fi
        
        return 1
      }

      if [[ $# -eq 1 ]]; then
          selected_path=$(resolve_path "$1")
          if [[ -z "$selected_path" ]]; then
              echo "Error: Directory '$1' not found"
              exit 1
          fi
      else
          selected_path=$(find ~/repositories ~/system-manifest -mindepth 1 -maxdepth 2 -type d | fzf)
      fi

      if [[ -z $selected_path ]]; then
          exit 0
      fi

      selected_name=$(basename "$selected_path" | tr . _)

      if [[ -z $ZELLIJ ]]; then
          cd "$selected_path" || exit 1
          if zellij list-sessions 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | grep -qF "$selected_name"; then
              zellij attach "$selected_name"
          else
              zellij attach -c "$selected_name"
          fi
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
            pane size=2 borderless=true {
                plugin location="zellij:status-bar"
            }
        }
        
        tab name="vim" focus=true {
            pane split_direction="horizontal" {
                pane size="80%" command="nvim" focus=true
                pane size="20%"
            }
        }

        tab name="copilot" {
            pane command="gh" {
                args "copilot";
            }
        }
    }
  '';

  home.shellAliases = {
    zellij-sessionizer = "zs ~/repositories";
  };
}
