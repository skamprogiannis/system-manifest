{
  pkgs,
  steamWeAssetsDir,
  steamWorkshopDir,
}: let
  skwdWeCaptureStill = pkgs.writeShellScriptBin "skwd-we-capture-still" ''
        set -euo pipefail

        assets_dir="${steamWeAssetsDir}"
        workshop_dir="${steamWorkshopDir}"
        cache_dir="$HOME/.cache/skwd-wall/wallpaper/we-captures"

        usage() {
          cat <<'EOF'
    Usage: skwd-we-capture-still [--current] [--current-live] <we-id>

    Capture a 1920x1080 still image for a Wallpaper Engine item and store it at:
      ~/.cache/skwd-wall/wallpaper/we-captures/<we-id>.jpg

    Options:
      --current       Capture by the currently selected WE wallpaper ID using offscreen render
      --current-live  Capture the currently visible monitor output with grim after a short delay
    EOF
        }

        thumb_is_near_black() {
          local thumb="$1"
          [ -f "$thumb" ] || return 1
          local brightness=""
          brightness=$(${pkgs.imagemagick}/bin/magick "''${thumb}[0]" \
            -colorspace Gray -resize 1x1\! -depth 8 gray:- 2>/dev/null \
            | ${pkgs.coreutils}/bin/od -An -tu1 \
            | ${pkgs.gawk}/bin/awk 'NF { print $1; exit }')
          [ -n "$brightness" ] || return 1
          [ "$brightness" -le 3 ]
        }

        resolve_current_we_id() {
          ${pkgs.python3}/bin/python3 <<'PY'
    from pathlib import Path
    import json
    state = Path.home() / ".cache" / "skwd-wall" / "last-wallpaper.json"
    if not state.exists():
        raise SystemExit(1)
    data = json.loads(state.read_text())
    wid = data.get("we_id")
    if isinstance(wid, str) and wid.isdigit():
        print(wid)
        raise SystemExit(0)
    raise SystemExit(1)
    PY
        }

        we_id=""
        capture_mode="offscreen"
        case "''${1:-}" in
          --current)
            we_id="$(resolve_current_we_id)"
            ;;
          --current-live)
            we_id="$(resolve_current_we_id)"
            capture_mode="live"
            ;;
          -h|--help|"")
            usage
            [ "$#" -gt 0 ] || exit 1
            exit 0
            ;;
          *)
            we_id="$1"
            ;;
        esac

        if ! [[ "$we_id" =~ ^[0-9]+$ ]]; then
          echo "skwd-we-capture-still: invalid we-id: $we_id" >&2
          exit 2
        fi

        we_dir="$workshop_dir/$we_id"
        if [ ! -d "$we_dir" ]; then
          echo "skwd-we-capture-still: missing workshop dir: $we_dir" >&2
          exit 1
        fi

        mkdir -p "$cache_dir"
        dst="$cache_dir/$we_id.jpg"
        tmp_png=$(mktemp /tmp/skwd-we-capture-XXXXXX.png)
        tmp_jpg=$(mktemp /tmp/skwd-we-capture-XXXXXX.jpg)
        trap 'rm -f "$tmp_png" "$tmp_jpg"' EXIT

        capture_live_monitor() {
          local monitor_name=""
          monitor_name=$(hyprctl monitors -j 2>/dev/null \
            | ${pkgs.jq}/bin/jq -r '.[] | select(.focused == true) | .name' \
            | ${pkgs.coreutils}/bin/head -n 1)
          echo "Capturing live monitor in 2 seconds..." >&2
          sleep 2
          if [ -n "$monitor_name" ]; then
            ${pkgs.grim}/bin/grim -o "$monitor_name" "$tmp_png" 2>/dev/null
          else
            ${pkgs.grim}/bin/grim "$tmp_png" 2>/dev/null
          fi
          [ -s "$tmp_png" ] || return 1
          thumb_is_near_black "$tmp_png" && return 1
          return 0
        }

        capture_attempt() {
          local delay="$1"
          rm -f "$tmp_png"
          ${pkgs.linux-wallpaperengine}/bin/linux-wallpaperengine \
            --assets-dir "$assets_dir" \
            --window 0x0x1920x1080 \
            --screenshot "$tmp_png" \
            --screenshot-delay "$delay" \
            --fps 1 \
            --silent \
            --disable-mouse \
            "$we_dir" >/dev/null 2>&1 &
          local pid=$!
          local waited=0
          local max_wait=$(( (delay + 7) * 5 ))
          while [ ! -s "$tmp_png" ] && kill -0 "$pid" 2>/dev/null && [ "$waited" -lt "$max_wait" ]; do
            sleep 0.2
            waited=$((waited + 1))
          done
          if kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null || true
            local kill_wait=0
            while kill -0 "$pid" 2>/dev/null && [ "$kill_wait" -lt 10 ]; do
              sleep 0.2
              kill_wait=$((kill_wait + 1))
            done
            if kill -0 "$pid" 2>/dev/null; then
              kill -9 "$pid" 2>/dev/null || true
            fi
          fi
          wait "$pid" 2>/dev/null || true
          [ -s "$tmp_png" ] || return 1
          thumb_is_near_black "$tmp_png" && return 1
          return 0
        }

        captured=0
        if [ "$capture_mode" = "live" ]; then
          if capture_live_monitor; then
            captured=1
          fi
        else
          for delay in 5 8; do
            if capture_attempt "$delay"; then
              captured=1
              break
            fi
          done
        fi

        if [ "$captured" -ne 1 ]; then
          echo "skwd-we-capture-still: failed to render still for $we_id" >&2
          exit 1
        fi

        ${pkgs.imagemagick}/bin/magick "$tmp_png" \
          -strip -colorspace sRGB -filter Lanczos \
          -resize 1920x1080^ -gravity center -extent 1920x1080 \
          -quality 95 "jpg:$tmp_jpg"
        install -m 644 "$tmp_jpg" "$dst"
        echo "$dst"
  '';
in {
  inherit skwdWeCaptureStill;
}
