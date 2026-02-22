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
        theme = "dracula";
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
              // Tab Switching (Both Ctrl and Alt)
              bind "Ctrl 1" "Alt 1" { GoToTab 1; }
              bind "Ctrl 2" "Alt 2" { GoToTab 2; }
              bind "Ctrl 3" "Alt 3" { GoToTab 3; }
              bind "Ctrl 4" "Alt 4" { GoToTab 4; }
              bind "Ctrl 5" "Alt 5" { GoToTab 5; }
              bind "Ctrl 6" "Alt 6" { GoToTab 6; }
              bind "Ctrl 7" "Alt 7" { GoToTab 7; }
              bind "Ctrl 8" "Alt 8" { GoToTab 8; }
              bind "Ctrl 9" "Alt 9" { GoToTab 9; }

              // Navigation
              bind "Ctrl Tab" { GoToNextTab; }
              bind "Ctrl Shift Tab" { GoToPreviousTab; }
              bind "Alt h" { MoveFocus "Left"; }
              bind "Alt l" { MoveFocus "Right"; }
              bind "Alt j" { MoveFocus "Down"; }
              bind "Alt k" { MoveFocus "Up"; }

              // Pane/Tab Management
              bind "Alt n" { NewPane "Down"; }
              bind "Alt x" { CloseFocus; }
              bind "Alt t" { NewTab; }
              bind "Alt w" { CloseTab; }
              bind "Alt s" { SwitchToMode "Scroll"; }
              bind "Alt o" { SwitchToMode "Session"; }
          }
      }
    '';
  };

  home.file."${config.xdg.configHome}/zellij/themes/dracula.kdl".text = ''
    themes {
        dracula {
            fg 248 248 242
            bg 40 42 54
            black 0 0 0
            red 255 85 85
            green 80 250 123
            yellow 241 250 140
            blue 98 114 164
            magenta 255 121 198
            cyan 139 233 253
            white 255 255 255
            orange 255 184 108
        }
    }
  '';

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
