{ctx}: let
  inherit
    (ctx)
    codexConfigPython
    desktopActivation
    desktopHome
    desktopZellijDevLayoutFile
    pkgs
    updateUsbSourceDir
    usbDmsServiceEnvironmentFile
    usbHome
    ;
in {
  script-smoke =
    pkgs.runCommand "script-smoke-checks" {
      nativeBuildInputs = [
        pkgs.gnugrep
        pkgs.gnused
      ];
    } ''
      set -euo pipefail

      desktop_home="${desktopHome}"
      desktop_activation="${desktopActivation}"
      update_usb_source_dir="${updateUsbSourceDir}"
      usb_home="${usbHome}"
      export HOME="$TMPDIR/home"
      export XDG_RUNTIME_DIR="$TMPDIR/runtime"
      mkdir -p "$HOME" "$XDG_RUNTIME_DIR"

      run_expect() {
        local expected_status="$1"
        local label="$2"
        shift 2

        local log="$TMPDIR/$label.log"
        set +e
        "$@" >"$log" 2>&1
        local status=$?
        set -e

        if [ "$status" -ne "$expected_status" ]; then
          echo "Unexpected exit status for $label: got $status, expected $expected_status" >&2
          ${pkgs.gnused}/bin/sed 's/^/  /' "$log" >&2
          exit 1
        fi

        LAST_LOG="$log"
      }

      assert_log_contains() {
        local needle="$1"
        if ! ${pkgs.gnugrep}/bin/grep -Fq "$needle" "$LAST_LOG"; then
          echo "Expected to find '$needle' in $LAST_LOG" >&2
          ${pkgs.gnused}/bin/sed 's/^/  /' "$LAST_LOG" >&2
          exit 1
        fi
      }

      run_expect 0 setup-persistent-usb-help "$usb_home/bin/setup-persistent-usb" --help
      assert_log_contains "Creates a fresh persistent NixOS USB"

      run_expect 1 update-usb-invalid-mode "$desktop_home/bin/update-usb" --mode nope
      assert_log_contains "Error: invalid mode 'nope'."

      run_expect 0 update-usb-help "$desktop_home/bin/update-usb" --help
      assert_log_contains "sudo update-usb [--mode prebuild|in-place] [--in-place] [--force] [path-to-flake-dir]"

      if ! ${pkgs.gnugrep}/bin/grep -Fq "#/nix/store/}/init" "$update_usb_source_dir/metadata.sh"; then
        echo "Expected update-usb to normalize squashfs verification paths relative to /nix/store." >&2
        ${pkgs.gnused}/bin/sed -n '1,120p' "$update_usb_source_dir/metadata.sh" >&2
        exit 1
      fi

      if ! ${pkgs.gnugrep}/bin/grep -Fq "cryptsetup close --deferred" "$update_usb_source_dir/cleanup.sh"; then
        echo "Expected update-usb cleanup to defer LUKS close until nested mounts release." >&2
        ${pkgs.gnused}/bin/sed -n '1,140p' "$update_usb_source_dir/cleanup.sh" >&2
        exit 1
      fi

      if ! ${pkgs.gnugrep}/bin/grep -Fq "findmnt -Rrn" "$update_usb_source_dir/cleanup.sh"; then
        echo "Expected update-usb cleanup to unmount nested filesystems deepest-first." >&2
        ${pkgs.gnused}/bin/sed -n '1,140p' "$update_usb_source_dir/cleanup.sh" >&2
        exit 1
      fi

      if ! ${pkgs.gnugrep}/bin/grep -Fq "#nixosConfigurations.usb.config.system.build.toplevel" "$update_usb_source_dir/metadata.sh"; then
        echo "Expected update-usb to prebuild the USB system toplevel attribute directly." >&2
        ${pkgs.gnused}/bin/sed -n '1,80p' "$update_usb_source_dir/metadata.sh" >&2
        exit 1
      fi

      if ! ${pkgs.gnugrep}/bin/grep -Fq "Existing USB squashfs already contains the desired system; skipping update." "$update_usb_source_dir/squashfs.sh"; then
        echo "Expected update-usb to skip duplicate squashfs copies when the desired system is already present." >&2
        ${pkgs.gnused}/bin/sed -n '1,120p' "$update_usb_source_dir/squashfs.sh" >&2
        exit 1
      fi

      run_expect 0 gsr-record-help "$desktop_home/bin/gsr-record" --help
      assert_log_contains "Usage: gsr-record"

      run_expect 1 gsr-record-invalid-mode "$desktop_home/bin/gsr-record" nope
      assert_log_contains "Error: unknown mode 'nope'."

      run_expect 1 transmission-port-sync-invalid-port "$desktop_home/bin/transmission-port-sync" 0
      assert_log_contains "Error: port must be an integer between 1 and 65535."

      if ! ${pkgs.gnugrep}/bin/grep -Fq 'command="${pkgs.bashInteractive}/bin/bash"' ${desktopZellijDevLayoutFile}; then
        echo "Expected zellij dev layout to launch Codex through a shell." >&2
        ${pkgs.gnused}/bin/sed -n '/tab name="codex"/,/}/p' ${desktopZellijDevLayoutFile} >&2
        exit 1
      fi

      if ! ${pkgs.gnugrep}/bin/grep -Fq 'args "-lc" "exec codex"' ${desktopZellijDevLayoutFile}; then
        echo "Expected zellij dev layout to start Codex like a shell-launched command." >&2
        ${pkgs.gnused}/bin/sed -n '/tab name="codex"/,/}/p' ${desktopZellijDevLayoutFile} >&2
        exit 1
      fi

      if ! ${pkgs.gnugrep}/bin/grep -Fq "skwd-daemon.service.d/livefix.conf" "$desktop_activation/activate"; then
        echo "Expected Home Manager activation to remove stale skwd-daemon livefix drop-ins." >&2
        ${pkgs.gnused}/bin/sed -n '/cleanupLegacySkwdDaemonLivefix/,/fi/p' "$desktop_activation/activate" >&2
        exit 1
      fi

      assert_log_contains_file() {
        local needle="$1"
        local file="$2"
        local message="$3"
        if ! ${pkgs.gnugrep}/bin/grep -Fq "$needle" "$file"; then
          echo "$message" >&2
          ${pkgs.gnused}/bin/sed 's/^/  /' "$file" >&2
          exit 1
        fi
      }

      assert_log_contains_file \
        "DMS_FORCE_EXT_WORKSPACE=1" \
        ${usbDmsServiceEnvironmentFile} \
        "Expected USB DMS service to force ext-workspace state instead of the fragile Hyprland event socket."

      if ! ${pkgs.gnugrep}/bin/grep -Fq "/bin/merge-codex-config" "$desktop_activation/activate"; then
        echo "Expected Home Manager activation to call the generated Codex config merger." >&2
        ${pkgs.gnused}/bin/sed -n '/ensureWritableCodexConfig/,/Activating/p' "$desktop_activation/activate" >&2
        exit 1
      fi

      codex_seed="$TMPDIR/codex-seed.toml"
      cat > "$codex_seed" <<'TOML'
      model = "gpt-5.5"
      approval_policy = "on-request"

      [tui]
      vim_mode_default = true

      [projects."/home/stefan/system-manifest"]
      trust_level = "trusted"

      [features]
      goals = true
      TOML

      run_codex_merge() {
        ${codexConfigPython}/bin/python3 ${../modules/home/codex/merge-config.py} "$codex_seed" "$1"
      }

      no_existing="$TMPDIR/codex/no-existing/config.toml"
      run_codex_merge "$no_existing"
      ${codexConfigPython}/bin/python3 - "$no_existing" <<'PY'
      import os
      from pathlib import Path
      import stat
      import sys
      import tomllib

      path = Path(sys.argv[1])
      with path.open("rb") as f:
          data = tomllib.load(f)

      assert data["model"] == "gpt-5.5"
      assert data["projects"]["/home/stefan/system-manifest"]["trust_level"] == "trusted"
      assert stat.S_IMODE(os.stat(path).st_mode) == 0o600
      PY

      existing_dir="$TMPDIR/codex/existing"
      existing="$existing_dir/config.toml"
      mkdir -p "$existing_dir"
      cat > "$existing" <<'TOML'
      model = "old"
      local_only = "kept"

      [features]
      local_flag = true
      goals = false

      [projects."/home/stefan/system-manifest"]
      trust_level = "untrusted"

      [projects."/tmp/other"]
      trust_level = "trusted"
      TOML
      run_codex_merge "$existing"
      ${codexConfigPython}/bin/python3 - "$existing" <<'PY'
      from pathlib import Path
      import sys
      import tomllib

      with Path(sys.argv[1]).open("rb") as f:
          data = tomllib.load(f)

      assert data["model"] == "gpt-5.5"
      assert data["local_only"] == "kept"
      assert data["features"]["goals"] is True
      assert data["features"]["local_flag"] is True
      assert data["projects"]["/home/stefan/system-manifest"]["trust_level"] == "trusted"
      assert data["projects"]["/tmp/other"]["trust_level"] == "trusted"
      PY

      malformed_dir="$TMPDIR/codex/malformed"
      malformed="$malformed_dir/config.toml"
      mkdir -p "$malformed_dir"
      printf '%s\n' '[broken' > "$malformed"
      run_codex_merge "$malformed"
      ${codexConfigPython}/bin/python3 - "$malformed_dir" "$malformed" <<'PY'
      from pathlib import Path
      import sys
      import tomllib

      directory = Path(sys.argv[1])
      config = Path(sys.argv[2])
      backups = list(directory.glob("config.toml.invalid-*"))
      assert len(backups) == 1
      assert backups[0].read_text() == "[broken\n"
      with config.open("rb") as f:
          data = tomllib.load(f)
      assert data["model"] == "gpt-5.5"
      PY

      if ${pkgs.gnugrep}/bin/grep -Fq "get key devices" "$desktop_home/bin/spotify_player"; then
        echo "spotify_player wrapper must not probe 'get key devices' because it can relaunch OAuth." >&2
        ${pkgs.gnused}/bin/sed -n '1,220p' "$desktop_home/bin/spotify_player" >&2
        exit 1
      fi

      if ! ${pkgs.gnugrep}/bin/grep -Fq "cached Spotify login expired; re-authenticating..." "$desktop_home/bin/spotify_player"; then
        echo "Expected spotify_player wrapper to recover stale cached Spotify logins." >&2
        ${pkgs.gnused}/bin/sed -n '1,220p' "$desktop_home/bin/spotify_player" >&2
        exit 1
      fi

      if ! ${pkgs.gnugrep}/bin/grep -Fq "Spotify Web API is rate-limited for the shared client ID" "$desktop_home/bin/spotify_player"; then
        echo "Expected spotify_player wrapper to surface shared-client rate limiting guidance." >&2
        ${pkgs.gnused}/bin/sed -n '1,260p' "$desktop_home/bin/spotify_player" >&2
        exit 1
      fi

      if ! ${pkgs.gnugrep}/bin/grep -Fq "Spotify client ID changed; clearing cached auth before re-authenticating" "$desktop_home/bin/spotify_player"; then
        echo "Expected spotify_player wrapper to clear cached auth when the configured client ID changes." >&2
        ${pkgs.gnused}/bin/sed -n '1,260p' "$desktop_home/bin/spotify_player" >&2
        exit 1
      fi

      if ! ${pkgs.gnugrep}/bin/grep -Fq "service_has_failed()" "$desktop_home/bin/spotify_player"; then
        echo "Expected spotify_player wrapper to detect failed daemon starts safely." >&2
        ${pkgs.gnused}/bin/sed -n '1,220p' "$desktop_home/bin/spotify_player" >&2
        exit 1
      fi

      if ! ${pkgs.gnugrep}/bin/grep -Fq "daemon_port=\"8082\"" "$desktop_home/bin/spotify_player"; then
        echo "Expected spotify_player wrapper to wait on the daemon-specific socket port." >&2
        ${pkgs.gnused}/bin/sed -n '1,220p' "$desktop_home/bin/spotify_player" >&2
        exit 1
      fi

      if ! ${pkgs.gnugrep}/bin/grep -Fq 'exec "$real_player" -c "$daemon_config_dir" "$@"' "$desktop_home/bin/spotify_player"; then
        echo "Expected spotify_player daemon-backed subcommands to use the daemon config." >&2
        ${pkgs.gnused}/bin/sed -n '1,240p' "$desktop_home/bin/spotify_player" >&2
        exit 1
      fi

      if ! ${pkgs.gnugrep}/bin/grep -Fq "spotify-player-tui.lock" "$desktop_home/bin/spotify_player"; then
        echo "Expected spotify_player wrapper to prevent duplicate TUI instances." >&2
        ${pkgs.gnused}/bin/sed -n '1,260p' "$desktop_home/bin/spotify_player" >&2
        exit 1
      fi

      if ! ${pkgs.gnugrep}/bin/grep -Fq "app_refresh_duration_in_ms = 32" ${../modules/home/spotify.nix}; then
        echo "Expected spotify module to keep fast periodic app refresh polling." >&2
        ${pkgs.gnused}/bin/sed -n '100,170p' ${../modules/home/spotify.nix} >&2
        exit 1
      fi

      if ! ${pkgs.gnugrep}/bin/grep -Fq "client_id_command = { command =" ${../modules/home/spotify.nix}; then
        echo "Expected spotify module to resolve the client ID via a command." >&2
        ${pkgs.gnused}/bin/sed -n '100,170p' ${../modules/home/spotify.nix} >&2
        exit 1
      fi

      if ! ${pkgs.gnugrep}/bin/grep -Fq "spotify-player auth OAuth block not found" ${../modules/home/spotify.nix}; then
        echo "Expected spotify module to patch the upstream auth flow to honor the configured client ID." >&2
        ${pkgs.gnused}/bin/sed -n '1,140p' ${../modules/home/spotify.nix} >&2
        exit 1
      fi

      touch "$out"
    '';
}
