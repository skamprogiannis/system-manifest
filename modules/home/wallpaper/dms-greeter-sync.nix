{
  pkgs,
  lib,
  skwdWallPkg,
  skwdWeCaptureStill,
  dmsWallpaperSessionSyncJson,
  allowedWallpaperTransitionsJson,
  includedWallpaperTransitionsJson,
  defaultWallpaperTransition,
}: let
  skwdDmsSyncHook = pkgs.writeShellScript "sync-dms-wallpaper.sh" ''
        set -euo pipefail

        # Ownership/order contract:
        # 1. skwd-wall owns wallpaper selection plus ~/.cache/skwd-wall/* state.
        # 2. This hook mirrors the selected wallpaper into DMS runtime state and
        #    the greeter cache after skwd-wall has produced a usable target.
        # 3. DMS and Hyprland consume that downstream state; they should not
        #    become writers for the shared wallpaper contract.
        current_wallpaper="$HOME/.cache/skwd-wall/wallpaper/current.jpg"
        last_wallpaper_state="$HOME/.cache/skwd-wall/last-wallpaper.json"
        session_dir="$HOME/.local/state/DankMaterialShell"
        greeter_cache_dir="/var/cache/dms-greeter"
        greeter_override="$greeter_cache_dir/greeter_wallpaper_override.jpg"
        greeter_settings="$greeter_cache_dir/settings.json"

        if [ ! -f "$current_wallpaper" ] && [ ! -f "$last_wallpaper_state" ]; then
          echo "sync-dms-wallpaper: missing both $current_wallpaper and $last_wallpaper_state" >&2
          exit 0
        fi

        mkdir -p "$session_dir"
        mkdir -p "$(dirname "$current_wallpaper")"
        export CURRENT_WALLPAPER_PATH="$current_wallpaper"
        export LAST_WALLPAPER_STATE="$last_wallpaper_state"
        export SKWD_BIN="${skwdWallPkg}/bin/skwd"
        export MAGICK_BIN="${pkgs.imagemagick}/bin/magick"
        export SKWD_CAPTURE_STILL_BIN="${skwdWeCaptureStill}/bin/skwd-we-capture-still"

        live_wallpaper="$(${pkgs.python3}/bin/python3 <<'PY'
    from pathlib import Path
    import json
    import mimetypes
    import os
    import shutil
    import subprocess
    import sys

    current = Path(os.environ["CURRENT_WALLPAPER_PATH"]).expanduser()
    state = Path(os.environ["LAST_WALLPAPER_STATE"]).expanduser()
    skwd = os.environ["SKWD_BIN"]
    magick = os.environ["MAGICK_BIN"]
    config = Path(os.path.expanduser("~/.config/skwd-wall/config.json"))
    capture_bin = os.environ.get("SKWD_CAPTURE_STILL_BIN", "").strip()
    _config_cache = None
    _wall_list_cache = None

    def load_json(path, *, log_errors=False):
        if not path.exists():
            return {}
        try:
            data = json.loads(path.read_text())
        except json.JSONDecodeError as exc:
            if log_errors:
                print(f"sync-dms-wallpaper: failed to parse {path}: {exc}", file=sys.stderr)
            return {}
        return data if isinstance(data, dict) else {}

    def load_state():
        return load_json(state, log_errors=True)

    def load_config():
        global _config_cache
        if _config_cache is None:
            _config_cache = load_json(config)
        return _config_cache

    def resolve_workshop_root():
        paths = load_config().get("paths")
        if isinstance(paths, dict):
            workshop = paths.get("steamWorkshop")
            if isinstance(workshop, str) and workshop:
                return Path(workshop).expanduser()
            steam_root = paths.get("steam")
            if isinstance(steam_root, str) and steam_root:
                return Path(steam_root).expanduser() / "steamapps" / "workshop" / "content" / "431960"
        return Path("~/.local/share/Steam/steamapps/workshop/content/431960").expanduser()

    def resolve_we_id(candidate, state_we_id=""):
        if isinstance(state_we_id, str) and state_we_id.isdigit():
            return state_we_id
        probes = [candidate, candidate.parent]
        for probe in probes:
            name = probe.name
            if name.isdigit():
                return name
        return ""

    def load_wall_list():
        global _wall_list_cache
        if _wall_list_cache is not None:
            return _wall_list_cache
        try:
            output = subprocess.check_output([skwd, "wall", "list", "{}"], text=True)
            payload = json.loads(output)
        except Exception as exc:
            print(f"sync-dms-wallpaper: failed to list wallpapers: {exc}", file=sys.stderr)
            _wall_list_cache = []
            return _wall_list_cache
        walls = payload.get("wallpapers") if isinstance(payload, dict) else None
        _wall_list_cache = walls if isinstance(walls, list) else []
        return _wall_list_cache

    def resolve_cached_thumb(we_id):
        if not we_id:
            return None
        for wall in load_wall_list():
            if not isinstance(wall, dict):
                continue
            if wall.get("we_id") != we_id and wall.get("key") != we_id:
                continue
            for field in ("thumb", "thumb_sm"):
                thumb = wall.get(field)
                if isinstance(thumb, str):
                    thumb_path = Path(thumb).expanduser()
                    if thumb_path.is_file():
                        return thumb_path
        return None

    def resolve_preview_source(we_id, candidate):
        workshop_root = resolve_workshop_root()
        probes = []
        if candidate is not None:
            probes.extend([candidate, candidate.parent])
        if we_id:
            probes.append(workshop_root / we_id)

        seen = set()
        for probe in probes:
            if probe is None:
                continue
            directory = probe if probe.is_dir() else probe.parent
            if not directory.exists():
                continue
            key = str(directory.resolve())
            if key in seen:
                continue
            seen.add(key)

            project = directory / "project.json"
            project_data = load_json(project)
            declared = project_data.get("preview")
            if isinstance(declared, str) and declared:
                declared_path = (directory / declared).expanduser()
                if declared_path.is_file():
                    return declared_path

            for name in (
                "preview.jpg",
                "preview.png",
                "preview.webp",
                "preview.bmp",
                "preview.gif",
                "thumbnail.jpg",
                "thumbnail.png",
                "thumbnail.webp",
            ):
                preview = directory / name
                if preview.is_file():
                    return preview
        return None

    def image_geometry(path):
        try:
            output = subprocess.check_output(
                [magick, "identify", "-format", "%w %h", f"{path}[0]"],
                text=True,
                stderr=subprocess.DEVNULL,
            ).strip()
            width, height = output.split()
            return int(width), int(height)
        except Exception:
            return None

    def preview_is_low_confidence(path):
        geometry = image_geometry(path)
        if geometry is None:
            return False
        width, height = geometry
        if height <= 0:
            return False
        ratio = width * 100 // height
        return width < 640 or height < 360 or ratio < 120 or ratio > 230

    def resolve_capture(we_id):
        if not we_id:
            return None
        capture = current.parent / "we-captures" / f"{we_id}.jpg"
        return capture if capture.is_file() else None

    def maybe_generate_capture(we_id, preview):
        if not we_id or not capture_bin:
            return None
        try:
            subprocess.run(
                [capture_bin, we_id],
                check=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.PIPE,
                text=True,
            )
        except subprocess.CalledProcessError as exc:
            message = exc.stderr.strip() or str(exc)
            print(f"sync-dms-wallpaper: failed to generate WE capture for {we_id}: {message}", file=sys.stderr)
            return None
        return resolve_capture(we_id)

    def resolve_we_source(we_id, candidate):
        capture = resolve_capture(we_id)
        if capture is not None:
            return capture
        thumb = resolve_cached_thumb(we_id)
        preview = resolve_preview_source(we_id, candidate)
        capture = maybe_generate_capture(we_id, preview)
        if capture is not None:
            return capture
        if thumb is not None and preview is not None:
            return thumb if preview_is_low_confidence(preview) else preview
        return thumb or preview

    data = load_state()
    candidate_raw = data.get("path")
    candidate = Path(candidate_raw).expanduser() if isinstance(candidate_raw, str) and candidate_raw else None
    state_we_id = data.get("we_id") if isinstance(data.get("we_id"), str) else ""
    live = current if current.is_file() else None
    source = None
    uses_original_live_path = False

    if candidate is not None:
        mime, _ = mimetypes.guess_type(str(candidate))
        if candidate.is_file() and isinstance(mime, str) and mime.startswith("image/"):
            source = candidate
            live = candidate
            uses_original_live_path = True
        else:
            source = resolve_we_source(resolve_we_id(candidate, state_we_id), candidate)

    if source is None and state_we_id:
        source = resolve_we_source(state_we_id, candidate)

    if source is None and current.is_file():
        source = current

    if source is not None:
        tmp = current.with_name(current.name + ".tmp")
        try:
            subprocess.run(
                [
                    magick,
                    f"{source}[0]",
                    "-auto-orient",
                    "-strip",
                    "-background",
                    "black",
                    "-alpha",
                    "remove",
                    "-alpha",
                    "off",
                    "-colorspace",
                    "sRGB",
                    "-quality",
                    "95",
                    f"jpg:{tmp}",
                ],
                check=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.PIPE,
                text=True,
            )
        except subprocess.CalledProcessError as exc:
            message = exc.stderr.strip() or str(exc)
            print(f"sync-dms-wallpaper: failed to normalize preview {source}: {message}", file=sys.stderr)
            if tmp.exists():
                tmp.unlink()
        else:
            os.replace(tmp, current)
            current.chmod(0o644)
            if state_we_id and not uses_original_live_path:
                live_target = current.with_name(f"we-live-{state_we_id}.jpg")
                tmp_live = live_target.with_name(live_target.name + ".tmp")
                try:
                    shutil.copyfile(current, tmp_live)
                except OSError as exc:
                    print(f"sync-dms-wallpaper: failed to write live WE wallpaper {live_target}: {exc}", file=sys.stderr)
                    if tmp_live.exists():
                        tmp_live.unlink()
                    live = current
                else:
                    os.replace(tmp_live, live_target)
                    live_target.chmod(0o644)
                    live = live_target
            elif not uses_original_live_path:
                live = current

    print(str(live) if live and live.exists() else "")
    PY
        )"
        if [ -z "$live_wallpaper" ] || [ ! -e "$live_wallpaper" ]; then
          echo "sync-dms-wallpaper: no usable live wallpaper path" >&2
          exit 0
        fi
        export LIVE_WALLPAPER_PATH="$live_wallpaper"

        ${pkgs.python3}/bin/python3 <<'PY'
    from pathlib import Path
    import json
    import os
    import sys

    wallpaper = Path(os.environ["LIVE_WALLPAPER_PATH"])
    session_file = Path(os.path.expanduser("~/.local/state/DankMaterialShell/session.json"))

    if session_file.exists():
        try:
            data = json.loads(session_file.read_text())
        except json.JSONDecodeError as exc:
            # Fail closed on malformed authoritative targets so runtime sync
            # does not clobber live DMS session state unexpectedly. Activation
            # owns healing this file back to defaults beforehand.
            print(f"sync-dms-wallpaper: failed to parse {session_file}: {exc}", file=sys.stderr)
            sys.exit(1)
    else:
        data = {}

    wallpaper_path = str(wallpaper)
    sync_contract = json.loads(${lib.escapeShellArg dmsWallpaperSessionSyncJson})
    for key, value in sync_contract["forcedFlags"].items():
        data[key] = value
    for key in sync_contract["wallpaperPathKeys"]:
        data[key] = wallpaper_path

    for key in sync_contract["monitorWallpaperKeys"]:
        data[key] = {}

    monitor_cycling_key = sync_contract["monitorCyclingSettingsKey"]
    if monitor_cycling_key in data:
        data[monitor_cycling_key] = {}
    config_file = Path(os.path.expanduser("~/.config/skwd-wall/config.json"))
    if config_file.exists():
        try:
            config = json.loads(config_file.read_text())
            mode = config.get("matugen", {}).get("mode")
            data["isLightMode"] = mode == "light"
        except json.JSONDecodeError as exc:
            # Best-effort reads from auxiliary config should warn and continue.
            print(f"sync-dms-wallpaper: failed to parse {config_file}: {exc}", file=sys.stderr)
    allowed_transitions = set(json.loads(${lib.escapeShellArg allowedWallpaperTransitionsJson}))
    if data.get("wallpaperTransition") not in allowed_transitions:
        data["wallpaperTransition"] = "${defaultWallpaperTransition}"
    if not isinstance(data.get("includedTransitions"), list) or not data["includedTransitions"]:
        data["includedTransitions"] = json.loads(${lib.escapeShellArg includedWallpaperTransitionsJson})

    payload = json.dumps(data, separators=(",", ":")) + "\n"
    current_payload = session_file.read_text() if session_file.exists() else ""
    if current_payload != payload:
        tmp_file = session_file.with_name(session_file.name + ".tmp")
        tmp_file.write_text(payload)
        tmp_file.chmod(0o600)
        os.replace(tmp_file, session_file)
        print("changed")
    else:
        print("unchanged")
    PY

        export GREETER_OVERRIDE_PATH="$greeter_override"
        if [ ! -f "$live_wallpaper" ]; then
          echo "sync-dms-wallpaper: missing live wallpaper still for greeter" >&2
        elif [ -d "$greeter_cache_dir" ] && [ -w "$greeter_cache_dir" ]; then
          install -m 664 "$live_wallpaper" "$greeter_override.tmp"
          mv -f "$greeter_override.tmp" "$greeter_override"
          chmod 664 "$greeter_override"

          ${pkgs.python3}/bin/python3 <<'PY'
    from pathlib import Path
    import json
    import os
    import sys

    settings_file = Path("/var/cache/dms-greeter/settings.json")
    wallpaper = Path(os.environ["GREETER_OVERRIDE_PATH"])

    if settings_file.exists():
        try:
            data = json.loads(settings_file.read_text())
        except json.JSONDecodeError as exc:
            # Greeter settings are another authoritative write target, so keep
            # the same fail-closed policy as DMS session.json.
            print(f"sync-dms-wallpaper: failed to parse {settings_file}: {exc}", file=sys.stderr)
            sys.exit(1)
    else:
        data = {}

    data["greeterWallpaperPath"] = str(wallpaper)
    payload = json.dumps(data, separators=(",", ":")) + "\n"
    current_payload = settings_file.read_text() if settings_file.exists() else ""
    if current_payload != payload:
        tmp_file = settings_file.with_name(settings_file.name + ".tmp")
        tmp_file.write_text(payload)
        tmp_file.chmod(0o664)
        os.replace(tmp_file, settings_file)
    PY
          chmod 664 "$greeter_settings"
        else
          echo "sync-dms-wallpaper: greeter cache dir not writable: $greeter_cache_dir" >&2
        fi
  '';
in {
  inherit skwdDmsSyncHook;
}
