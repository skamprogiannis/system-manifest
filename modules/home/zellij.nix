{
  config,
  lib,
  pkgs,
  ...
}: let
  zellijUnwrappedWithForwardedBells = pkgs.zellij-unwrapped.overrideAttrs (old: {
    patchFlags = (old.patchFlags or []) ++ ["-p0"];
    patches = (old.patches or []) ++ [./zellij-forward-all-bells.patch];
  });
  zellijWithForwardedBells = pkgs.zellij.overrideAttrs (_old: {
    src = zellijUnwrappedWithForwardedBells;
  });
  zellijPostCommandDiscoveryHook = pkgs.writeShellScript "zellij-post-command-discovery-hook" ''
    resurrect_command="''${RESURRECT_COMMAND:-}"

    case "$resurrect_command" in
      npm\ exec\ @upstash/context7-mcp* | */npm\ exec\ @upstash/context7-mcp* | npm\ exec\ @softeria/ms-365-mcp-server* | */npm\ exec\ @softeria/ms-365-mcp-server*)
        printf '%s\n' "${pkgs.bashInteractive}/bin/bash -lc 'exec codex'"
        ;;
      *)
        printf '%s\n' "$resurrect_command"
        ;;
    esac
  '';
in {
  programs.zellij = {
    enable = true;
    enableBashIntegration = false;
    package = zellijWithForwardedBells;
    settings = {
      default_shell = "${pkgs.bashInteractive}/bin/bash";
      escape_timeout = 0;
      pane_frames = false;
      post_command_discovery_hook = "${zellijPostCommandDiscoveryHook}";
      simplified_ui = true;
      theme = "catppuccin-mocha";
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

          // Keep Enter behavior while preventing status-bar from preferring it in mode hints.
          // The extra NoOp keeps Enter functional but avoids matching "SwitchToMode Normal" hint patterns.
          shared_except "normal" "locked" {
            unbind "Enter"
            bind "Enter" { SwitchToMode "Normal"; NoOp; }
          }

          normal {
            // Esc is unbound so Vim, Codex etc. receive it uninterrupted
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

            // Move Pane (Alt+Shift)
            bind "Alt H" { MovePane "Left"; }
            bind "Alt J" { MovePane "Down"; }
            bind "Alt K" { MovePane "Up"; }
            bind "Alt L" { MovePane "Right"; }

            bind "Alt n" { NewTab; }
            bind "Alt f" { ToggleFloatingPanes; }
            bind "Alt x" { CloseFocus; }
            bind "Alt z" { ToggleFocusFullscreen; }
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
            bind "Alt [" { MoveTab "Left"; }
            bind "Alt ]" { MoveTab "Right"; }
            bind "Alt Shift Left" { MovePane "Left"; }
            bind "Alt Shift Right" { MovePane "Right"; }
            bind "Alt Shift Up" { MovePane "Up"; }
            bind "Alt Shift Down" { MovePane "Down"; }

            // Cycle tab layout
            bind "Alt ," { PreviousSwapLayout; }
            bind "Alt ." { NextSwapLayout; }
          }

          move {
            bind "Esc" { SwitchToMode "Normal"; }
            bind "h" { MovePane "Left"; }
            bind "l" { MovePane "Right"; }
            bind "j" { MovePane "Down"; }
            bind "k" { MovePane "Up"; }
          }

          pane {
            bind "Esc" { SwitchToMode "Normal"; }
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
            bind "Esc" { SwitchToMode "Normal"; }
            bind "h" "k" "Left" "Up" { GoToPreviousTab; }
            bind "l" "j" "Right" "Down" { GoToNextTab; }
            bind "Alt h" "Alt Left" { MoveTab "Left"; }
            bind "Alt l" "Alt Right" { MoveTab "Right"; }
          }

          resize {
            bind "Esc" { SwitchToMode "Normal"; }
            bind "h" { Resize "Increase Left"; }
            bind "j" { Resize "Increase Down"; }
            bind "k" { Resize "Increase Up"; }
            bind "l" { Resize "Increase Right"; }
            bind "H" { Resize "Decrease Left"; }
            bind "J" { Resize "Decrease Down"; }
            bind "K" { Resize "Decrease Up"; }
            bind "L" { Resize "Decrease Right"; }
            bind "=" "+" { Resize "Increase"; }
            bind "-" { Resize "Decrease"; }
          }

          session {
            bind "Esc" { SwitchToMode "Normal"; }
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
            bind "j" { ScrollDown; }
            bind "k" { ScrollUp; }
            bind "f" "PageDown" { PageScrollDown; }
            bind "b" "PageUp" { PageScrollUp; }
            bind "d" { HalfPageScrollDown; }
            bind "u" { HalfPageScrollUp; }
            bind "/" { SwitchToMode "EnterSearch"; SearchInput 0; }
            bind "e" { EditScrollback; SwitchToMode "Normal"; }
          }

          search {
            bind "j" { ScrollDown; }
            bind "k" { ScrollUp; }
            bind "f" "PageDown" { PageScrollDown; }
            bind "b" "PageUp" { PageScrollUp; }
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

  home.activation.scrubLegacyZellijContext7Args = lib.hm.dag.entryAfter ["writeBoundary"] ''
    # shellcheck shell=bash
    zellij_cache_root="''${XDG_CACHE_HOME:-$HOME/.cache}/zellij"
    if [[ -d "$zellij_cache_root" ]]; then
      while IFS= read -r -d "" session_layout; do
        session_layout_dir="$(${pkgs.coreutils}/bin/dirname "$session_layout")"
        scrubbed_layout="$(${pkgs.coreutils}/bin/mktemp --tmpdir="$session_layout_dir" .session-layout.kdl.XXXXXX)"

        if ! ${pkgs.gnused}/bin/sed -E \
          '/"@upstash\/context7-mcp/ s/[[:space:]]+"--api-key"[[:space:]]+"[^"]*"//g' \
          "$session_layout" > "$scrubbed_layout"; then
          ${pkgs.coreutils}/bin/rm -f "$scrubbed_layout"
          exit 1
        fi

        if ${pkgs.diffutils}/bin/cmp -s "$session_layout" "$scrubbed_layout"; then
          ${pkgs.coreutils}/bin/rm -f "$scrubbed_layout"
        else
          ${pkgs.coreutils}/bin/chmod 0600 "$scrubbed_layout"
          ${pkgs.coreutils}/bin/mv -f "$scrubbed_layout" "$session_layout"
          ${pkgs.coreutils}/bin/chmod 0600 "$session_layout"
        fi
      done < <(${pkgs.findutils}/bin/find "$zellij_cache_root" -type f -name session-layout.kdl -print0)
    fi
  '';

  home.packages = [
    (pkgs.writeShellScriptBin "zellij-sessionizer" ''
      resolve_path() {
        local input="$1"
        local query
        local cwd
        cwd=$(pwd)

        if [[ -z "$input" ]]; then
          return 1
        fi

        # Normalize trailing slashes so basename/session naming stays stable.
        query="$input"
        query="''${query%/}"
        [[ -z "$query" ]] && query="/"

        if [[ -d "$query" ]]; then
          echo "$query"
          return 0
        fi

        # Accept "/foo" shorthand as relative "foo" when absolute path does not exist.
        if [[ "$query" == /* ]] && [[ "$query" != "/" ]]; then
          query="''${query#/}"
        fi

        # Support relative paths from current directory (e.g. "go" in
        # ~/repositories/leetcode-style-problems/leetcode).
        if [[ -d "$cwd/$query" ]]; then
          echo "$cwd/$query"
          return 0
        fi

        if [[ -d ~/repositories/"$query" ]]; then
          echo ~/repositories/"$query"
          return 0
        fi

        nested_match=$(find ~/repositories -mindepth 2 -maxdepth 2 -type d -name "$query" -print -quit 2>/dev/null)
        if [[ -n "$nested_match" ]]; then
          echo "$nested_match"
          return 0
        fi

        if [[ -d ~/"$query" ]]; then
          echo ~/"$query"
          return 0
        fi

        return 1
      }

      session_name_for_path() {
        local path="$1"
        local common_dir
        local common_base
        local repo_root
        local repo_name
        local branch_name

        common_dir=$(git -C "$path" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 1
        common_base=$(basename "$common_dir")
        branch_name=$(git -C "$path" branch --show-current 2>/dev/null) || true

        if [[ "$common_base" == .* ]]; then
          repo_root=$(dirname "$common_dir")
        else
          repo_root="$common_dir"
        fi

        repo_name=$(basename "$repo_root")

        if [[ -n "$branch_name" ]]; then
          printf '%s\n' "''${repo_name}@''${branch_name}"
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

      selected_path=$(cd "$selected_path" 2>/dev/null && pwd -P)
      if [[ -z "$selected_path" ]]; then
          echo "Error: Could not resolve directory"
          exit 1
      fi

      selected_name=$(session_name_for_path "$selected_path" || basename "$selected_path")
      selected_name=$(printf '%s' "$selected_name" | sed 's/\./_/g; s#/#-#g')

      if [[ -z $ZELLIJ ]]; then
          cd "$selected_path" || exit 1
          session_listing=$(zellij list-sessions --no-formatting 2>/dev/null || true)
          session_state=absent
          session_prefix="$selected_name [Created "

          while IFS= read -r session_line; do
              if [[ "$session_line" == "$session_prefix"* ]]; then
                  session_state=live
                  if [[ "$session_line" == "$session_prefix"*"(EXITED"* ]]; then
                      session_state=exited
                  fi
                  break
              fi
          done <<< "$session_listing"

          case "$session_state" in
              live)
                  zellij attach "$selected_name"
                  ;;
              exited)
                  zellij_cache_root="''${XDG_CACHE_HOME:-$HOME/.cache}/zellij"
                  corrupt_snapshot=false
                  for session_layout in "$zellij_cache_root"/contract_version_*/session_info/"$selected_name"/session-layout.kdl; do
                      if [[ -f "$session_layout" ]] && ${pkgs.gawk}/bin/awk '
                          !in_npm_pane && /^[[:space:]]*pane([[:space:]]|$)/ && /command="npm"/ {
                              in_npm_pane = 1
                              pane_depth = 0
                          }

                          in_npm_pane {
                              if (/^[[:space:]]*args[[:space:]]+"exec"[[:space:]]+"@upstash\/context7-mcp/ || /^[[:space:]]*args[[:space:]]+"exec"[[:space:]]+"@softeria\/ms-365-mcp-server/) {
                                  corrupt = 1
                              }

                              braces = $0
                              opens = gsub(/\{/, "", braces)
                              braces = $0
                              closes = gsub(/\}/, "", braces)
                              pane_depth += opens - closes
                              if (pane_depth <= 0) {
                                  in_npm_pane = 0
                              }
                          }

                          END {
                              exit corrupt ? 0 : 1
                          }
                      ' "$session_layout"; then
                          corrupt_snapshot=true
                          break
                      fi
                  done

                  if [[ "$corrupt_snapshot" == true ]]; then
                      zellij attach --forget -c "$selected_name"
                  else
                      zellij attach "$selected_name"
                  fi
                  ;;
              absent)
                  zellij attach -c "$selected_name"
                  ;;
          esac
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
                plugin location="zellij:status-bar"
            }
        }

        tab name="vim" focus=true {
            pane name="nvim" command="/etc/profiles/per-user/${config.home.username}/bin/nvim" focus=true
        }

        tab name="codex" {
            pane name="codex" command="${pkgs.bashInteractive}/bin/bash" {
                args "-lc" "exec codex"
            }
        }

        tab_template name="dev_chrome" {
            pane size=1 borderless=true {
                plugin location="zellij:tab-bar"
            }
            children
            pane size=1 borderless=true {
                plugin location="zellij:status-bar"
            }
        }

        swap_tiled_layout name="vertical" {
            dev_chrome max_panes=5 {
                pane split_direction="vertical" {
                    pane
                    pane { children; }
                }
            }
            dev_chrome max_panes=8 {
                pane split_direction="vertical" {
                    pane { children; }
                    pane { pane; pane; pane; pane; }
                }
            }
            dev_chrome max_panes=12 {
                pane split_direction="vertical" {
                    pane { children; }
                    pane { pane; pane; pane; pane; }
                    pane { pane; pane; pane; pane; }
                }
            }
        }

        swap_tiled_layout name="horizontal" {
            dev_chrome max_panes=4 {
                pane
                pane
            }
            dev_chrome max_panes=8 {
                pane {
                    pane split_direction="vertical" { children; }
                    pane split_direction="vertical" { pane; pane; pane; pane; }
                }
            }
            dev_chrome max_panes=12 {
                pane {
                    pane split_direction="vertical" { children; }
                    pane split_direction="vertical" { pane; pane; pane; pane; }
                    pane split_direction="vertical" { pane; pane; pane; pane; }
                }
            }
        }

        swap_tiled_layout name="stacked" {
            dev_chrome min_panes=5 {
                pane split_direction="vertical" {
                    pane
                    pane stacked=true { children; }
                }
            }
        }

        swap_floating_layout name="staggered" {
            floating_panes
        }

        swap_floating_layout name="enlarged" {
            floating_panes max_panes=10 {
                pane { x "5%"; y 1; width "90%"; height "90%"; }
                pane { x "5%"; y 2; width "90%"; height "90%"; }
                pane { x "5%"; y 3; width "90%"; height "90%"; }
                pane { x "5%"; y 4; width "90%"; height "90%"; }
                pane { x "5%"; y 5; width "90%"; height "90%"; }
                pane { x "5%"; y 6; width "90%"; height "90%"; }
                pane { x "5%"; y 7; width "90%"; height "90%"; }
                pane { x "5%"; y 8; width "90%"; height "90%"; }
                pane { x "5%"; y 9; width "90%"; height "90%"; }
                pane { x 10; y 10; width "90%"; height "90%"; }
            }
        }

        swap_floating_layout name="spread" {
            floating_panes max_panes=1 {
                pane { y "50%"; x "50%"; }
            }
            floating_panes max_panes=2 {
                pane { x "1%"; y "25%"; width "45%"; }
                pane { x "50%"; y "25%"; width "45%"; }
            }
            floating_panes max_panes=3 {
                pane { y "55%"; width "45%"; height "45%"; }
                pane { x "1%"; y "1%"; width "45%"; }
                pane { x "50%"; y "1%"; width "45%"; }
            }
            floating_panes max_panes=4 {
                pane { x "1%"; y "55%"; width "45%"; height "45%"; }
                pane { x "50%"; y "55%"; width "45%"; height "45%"; }
                pane { x "1%"; y "1%"; width "45%"; height "45%"; }
                pane { x "50%"; y "1%"; width "45%"; height "45%"; }
            }
        }
    }
  '';

  home.shellAliases = {
    zs = "zellij-sessionizer";
  };
}
