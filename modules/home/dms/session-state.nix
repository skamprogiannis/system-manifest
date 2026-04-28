{
  lib,
  ...
}: let
  sessionDefaultsJson = builtins.toJSON {
    nightModeEnabled = false;
    nightModeAutoEnabled = false;
    themeModeAutoEnabled = false;
    themeModeShareGammaSettings = false;
    nightModeUseIPLocation = false;
  };
in {
  xdg.configFile."DankMaterialShell/.firstlaunch".text = "";

  home.activation.ensureWritableDmsSession = lib.hm.dag.entryAfter ["writeBoundary"] ''
    state_dir="$HOME/.local/state/DankMaterialShell"
    session_file="$state_dir/session.json"
    tmp_file=""

    write_defaults() {
      printf '%s\n' ${lib.escapeShellArg sessionDefaultsJson} > "$1"
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
      chmod 600 "$session_file"
    fi
  '';
}
