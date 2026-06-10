{
  pkgs,
  defaultWallpaperTransition,
}: let
  skwdApplyStaticWallpaper = pkgs.writeShellScript "apply-static-wallpaper.sh" ''
    set -euo pipefail

    wallpaper_path="$1"
    outputs_csv="''${2:-}"
    session_file="$HOME/.local/state/DankMaterialShell/session.json"
    transition="${defaultWallpaperTransition}"
    transition_type="center"
    transition_duration="0.45"
    transition_step="72"
    transition_fps="60"
    transition_pos="center"
    transition_bezier=""

    if [ -f "$session_file" ]; then
      transition="$(${pkgs.jq}/bin/jq -r '.wallpaperTransition // "${defaultWallpaperTransition}"' "$session_file" 2>/dev/null || printf '${defaultWallpaperTransition}\n')"
    fi

    case "$transition" in
      none)
        transition_type="simple"
        transition_duration="0"
        transition_step="255"
        ;;
      fade)
        transition_type="fade"
        transition_duration="0.5"
        transition_step="20"
        transition_fps="60"
        transition_bezier=".42,0,.58,1"
        ;;
      wipe)
        transition_type="wipe"
        transition_duration="0.6"
        transition_step="24"
        transition_fps="60"
        ;;
      disc|portal|"iris bloom")
        transition_type="center"
        transition_duration="0.45"
        transition_step="72"
        transition_fps="60"
        transition_pos="center"
        ;;
      stripes)
        transition_type="outer"
        transition_duration="0.6"
        transition_step="20"
        transition_fps="60"
        transition_pos="center"
        ;;
      pixelate)
        transition_type="any"
        transition_duration="0.55"
        transition_step="22"
        transition_fps="60"
        ;;
      random)
        transition_type="random"
        transition_duration="0.6"
        transition_step="18"
        transition_fps="60"
        ;;
      *)
        transition_type="center"
        transition_duration="0.45"
        transition_step="72"
        transition_fps="60"
        transition_pos="center"
        ;;
    esac

    daemon_ready() {
      ${pkgs.awww}/bin/awww query >/dev/null 2>&1
    }

    if ! daemon_ready; then
      setsid ${pkgs.awww}/bin/awww-daemon >/dev/null 2>&1 &
      for _ in 1 2 3 4 5 6 7 8 9 10; do
        sleep 0.1
        daemon_ready && break
      done
    fi

    cmd=(${pkgs.awww}/bin/awww img)
    if [ -n "$outputs_csv" ]; then
      cmd+=(-o "$outputs_csv")
    fi
    cmd+=("$wallpaper_path" --transition-type "$transition_type" --transition-duration "$transition_duration")
    if [ -n "$transition_step" ]; then
      cmd+=(--transition-step "$transition_step")
    fi
    if [ -n "$transition_fps" ]; then
      cmd+=(--transition-fps "$transition_fps")
    fi
    if [ -n "$transition_pos" ]; then
      cmd+=(--transition-pos "$transition_pos")
    fi
    if [ -n "$transition_bezier" ]; then
      cmd+=(--transition-bezier "$transition_bezier")
    fi
    if [ "$transition_type" = "wipe" ]; then
      cmd+=(--transition-angle 45)
    fi

    exec "''${cmd[@]}"
  '';
in {
  inherit skwdApplyStaticWallpaper;
}
