{pkgs, ...}: {
  home.packages = [
    (pkgs.writeShellScriptBin "ai-search" ''
      set -euo pipefail

      usage() {
        printf '%s\n' 'Usage: ai-search {start|stop|status}'
      }

      if [ "$#" -ne 1 ]; then
        usage >&2
        exit 2
      fi

      case "$1" in
        start)
          ${pkgs.sudo}/bin/sudo ${pkgs.systemd}/bin/systemctl start searx.service
          ${pkgs.sudo}/bin/sudo ${pkgs.systemd}/bin/systemctl start open-webui.service
          printf '%s\n' 'Open WebUI: http://127.0.0.1:8080'
          ;;
        stop)
          ${pkgs.sudo}/bin/sudo ${pkgs.systemd}/bin/systemctl stop open-webui.service searx.service
          printf '%s\n' 'AI search services stopped.'
          ;;
        status)
          printf 'Open WebUI: %s\n' "$(${pkgs.systemd}/bin/systemctl is-active open-webui.service || true)"
          printf 'SearXNG:    %s\n' "$(${pkgs.systemd}/bin/systemctl is-active searx.service || true)"
          ;;
        *)
          usage >&2
          exit 2
          ;;
      esac
    '')
  ];
}
