{
  lib,
  pkgs,
  ...
}: let
  wallpaperContracts = import ../wallpaper/contracts.nix;
  sessionDefaultsJson = builtins.toJSON wallpaperContracts.dmsSessionDefaults;
  allowedTransitionsJson = builtins.toJSON wallpaperContracts.wallpaperTransitions.allowed;
in {
  xdg.configFile."DankMaterialShell/.firstlaunch".text = "";

  # Home Manager activation owns the baseline schema for
  # ~/.local/state/DankMaterialShell/session.json. Missing, malformed, or
  # non-object content is healed back to defaults here so later runtime hooks
  # can assume a sane floor without widening the shared contract.
  home.activation.ensureWritableDmsSession = lib.hm.dag.entryAfter ["writeBoundary"] ''
    state_dir="$HOME/.local/state/DankMaterialShell"
    session_file="$state_dir/session.json"
    tmp_file=""

    write_defaults() {
      printf '%s\n' ${lib.escapeShellArg sessionDefaultsJson} > "$1"
    }

    normalize_session() {
      ${pkgs.python3}/bin/python3 - "$session_file" "$1" <<'PY'
from pathlib import Path
import json
import sys

session_path = Path(sys.argv[1])
output_path = Path(sys.argv[2])
defaults = json.loads(${lib.escapeShellArg sessionDefaultsJson})
allowed_transitions = set(json.loads(${lib.escapeShellArg allowedTransitionsJson}))

try:
    data = json.loads(session_path.read_text()) if session_path.exists() else {}
except json.JSONDecodeError:
    # Malformed activation-owned JSON is treated like a missing file: recover to
    # defaults here instead of failing activation.
    data = {}

if not isinstance(data, dict):
    data = {}

for key, value in defaults.items():
    if key not in data:
        data[key] = value

if data.get("wallpaperTransition") not in allowed_transitions:
    data["wallpaperTransition"] = defaults["wallpaperTransition"]

if not isinstance(data.get("includedTransitions"), list) or not data["includedTransitions"]:
    data["includedTransitions"] = defaults["includedTransitions"]

if not isinstance(data.get("isLightMode"), bool):
    data["isLightMode"] = defaults["isLightMode"]

output_path.write_text(json.dumps(data, separators=(",", ":")) + "\n")
PY
    }

    copy_or_reset_session() {
      if ! cat "$session_file" > "$1" 2>/dev/null; then
        write_defaults "$1"
      fi
    }

    cleanup() {
      if [ -n "$tmp_file" ]; then
        rm -f "$tmp_file"
      fi
    }
    trap cleanup EXIT

    mkdir -p "$state_dir"
    umask 077

    if [ -L "$session_file" ] || { [ -e "$session_file" ] && [ ! -w "$session_file" ]; }; then
      tmp_file="$(mktemp "$state_dir/session.json.XXXXXX")"
      copy_or_reset_session "$tmp_file"
      mv -f "$tmp_file" "$session_file"
      tmp_file=""
    elif [ ! -e "$session_file" ]; then
      tmp_file="$(mktemp "$state_dir/session.json.XXXXXX")"
      write_defaults "$tmp_file"
      mv -f "$tmp_file" "$session_file"
      tmp_file=""
    fi

    if [ -e "$session_file" ]; then
      tmp_file="$(mktemp "$state_dir/session.json.XXXXXX")"
      normalize_session "$tmp_file"
      if ! cmp -s "$session_file" "$tmp_file"; then
        mv -f "$tmp_file" "$session_file"
      else
        rm -f "$tmp_file"
      fi
      tmp_file=""
    fi

    if [ -e "$session_file" ]; then
      chmod 600 "$session_file"
    fi
  '';
}
