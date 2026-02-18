{
  config,
  lib,
  pkgs,
  ...
}: {
  programs.bash.initExtra = ''
    # VPN Control Tool (NetworkManager based)
    vpn() {
      case "$1" in
        on)
          # Default to Athens #1
          nmcli connection up GR-Athens-1
          ;;
        off)
          echo -e "\033[1;31mDeactivating all VPN connections...\033[0m"
          nmcli connection down GR-Athens-1 2>/dev/null
          nmcli connection down GR-Athens-26 2>/dev/null
          nmcli connection down US-DC-42 2>/dev/null
          nmcli connection down US-Seattle-33 2>/dev/null
          ;;
        switch)
          echo -e "\033[1;35m╔══════════════════════════════════════╗\033[0m"
          echo -e "\033[1;35m║\033[0m \033[1;36mSELECT VPN CONNECTION\033[0m                \033[1;35m║\033[0m"
          echo -e "\033[1;35m╠══════════════════════════════════════╣\033[0m"
          echo -e "\033[1;35m║\033[0m  1) GR-Athens-1                      \033[1;35m║\033[0m"
          echo -e "\033[1;35m║\033[0m  2) GR-Athens-26                     \033[1;35m║\033[0m"
          echo -e "\033[1;35m║\033[0m  3) US-DC-42                         \033[1;35m║\033[0m"
          echo -e "\033[1;35m║\033[0m  4) US-Seattle-33                    \033[1;35m║\033[0m"
          echo -e "\033[1;35m╚══════════════════════════════════════╝\033[0m"
          echo ""
          printf "\033[1;32m>\033[0m Select connection (1-4) or 'q' to abort: "
          read -r choice
          case "$choice" in
            1) vpn off >/dev/null 2>&1; nmcli connection up GR-Athens-1 ;;
            2) vpn off >/dev/null 2>&1; nmcli connection up GR-Athens-26 ;;
            3) vpn off >/dev/null 2>&1; nmcli connection up US-DC-42 ;;
            4) vpn off >/dev/null 2>&1; nmcli connection up US-Seattle-33 ;;
            q|Q) echo -e "\033[1;33mAborted.\033[0m" ;;
            *) echo -e "\033[1;31mError: Invalid selection.\033[0m" ;;
          esac
          ;;
        status)
          # Find any active Proton connections
          active_vpns=$(nmcli -t -f NAME,STATE connection show --active | grep -E "(GR-Athens|US-DC|US-Seattle)")
          if [ -n "$active_vpns" ]; then
            echo "$active_vpns" | while IFS=: read -r name state; do
              # Aesthetic formatting with Dracula colors
              printf "\033[1;35m🔒 VPN:\033[0m \033[1;36m%-15s\033[0m [\033[1;32m%s\033[0m]\n" "$name" "$state"
            done
          else
            echo -e "\033[1;35m🔓 VPN:\033[0m \033[1;33mDisconnected\033[0m"
          fi
          ;;
        import)
          if [ -z "$2" ]; then
            echo "Usage: vpn import <path-to-conf-file>"
            return 1
          fi
          filename=$(basename "$2")
          name="''${filename%.*}"
          echo -e "\033[1;34mImporting $name...\033[0m"
          sudo nmcli connection import type wireguard file "$2"
          nmcli connection modify "$name" connection.autoconnect no
          nmcli connection down "$name" 2>/dev/null
          echo -e "\033[1;32mDone. $name added (autoconnect disabled).\033[0m"
          ;;
        *)
          echo "Usage: vpn {on|off|status|switch|import}"
          ;;
      esac
    }

    _vpn_completion() {
      local cur prev opts
      COMPREPLY=()
      cur="''${COMP_WORDS[COMP_CWORD]}"
      # Balanced ordering for better tab-completion spacing
      opts="status switch on off import"
      COMPREPLY=( $(compgen -W "''${opts}" -- "''${cur}") )
    }
    complete -F _vpn_completion vpn
  '';
}
