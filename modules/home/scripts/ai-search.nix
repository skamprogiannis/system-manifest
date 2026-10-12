{pkgs, config, ...}: let
  systemctl = "${pkgs.systemd}/bin/systemctl";
  url = "http://127.0.0.1:8080";
in {
  home.packages = [
    (pkgs.writeShellScriptBin "ai-search" ''
      set -euo pipefail

      usage() {
        printf '%s\n' 'Usage: ai-search {start|stop|status|launch}'
      }

      if [ "$#" -ne 1 ]; then
        usage >&2
        exit 2
      fi

      case "$1" in
        start)
          ${systemctl} start open-webui.service
          printf 'Open WebUI: %s\n' '${url}'
          ;;
        stop)
          ${systemctl} stop open-webui.service
          printf '%s\n' 'Open WebUI stopped. SearXNG remains running.'
          ;;
        status)
          printf 'Open WebUI: %s\n' "$(${systemctl} is-active open-webui.service || true)"
          ;;
        launch)
          ${systemctl} start open-webui.service
          for _ in $(${pkgs.coreutils}/bin/seq 1 120); do
            if ${pkgs.curl}/bin/curl --fail --silent --max-time 2 --output /dev/null '${url}'; then
              exec ${config.programs.brave.finalPackage}/bin/brave '--app=${url}'
            fi
            ${pkgs.coreutils}/bin/sleep 1
          done
          ${pkgs.libnotify}/bin/notify-send 'Open WebUI' 'Server startup timed out. Check journalctl -u open-webui.'
          printf '%s\n' 'Open WebUI did not become available. Check journalctl -u open-webui.' >&2
          exit 1
          ;;
        help|--help|-h)
          usage
          ;;
        *)
          usage >&2
          exit 2
          ;;
      esac
    '')
    (pkgs.writeShellScriptBin "searxngctl" ''
      set -euo pipefail

      usage() {
        printf '%s\n' 'Usage: searxngctl {start|stop|status}'
      }

      if [ "$#" -ne 1 ]; then
        usage >&2
        exit 2
      fi

      case "$1" in
        start)
          ${systemctl} start searx.service
          printf '%s\n' 'SearXNG: http://127.0.0.1:8888'
          ;;
        stop)
          ${systemctl} stop searx.service
          printf '%s\n' 'SearXNG stopped. Open WebUI remains running.'
          ;;
        status)
          printf 'SearXNG: %s\n' "$(${systemctl} is-active searx.service || true)"
          ;;
        help|--help|-h)
          usage
          ;;
        *)
          usage >&2
          exit 2
          ;;
      esac
    '')
  ];

  xdg.desktopEntries.open-webui = {
    name = "Open WebUI";
    genericName = "Local AI Chat";
    comment = "Start Open WebUI and open it in an app window";
    exec = "ai-search launch";
    icon = "${pkgs.open-webui.src}/static/favicon.png";
    terminal = false;
    categories = ["Utility"];
  };
}
