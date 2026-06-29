{ctx}: let
  inherit
    (ctx)
    codexConfigPython
    desktopActivation
    desktopHome
    desktopZellijDevLayoutFile
    pkgs
    updateUsbSourceDir
    usbActivation
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
      usb_activation="${usbActivation}"
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
        if ! ${pkgs.gnugrep}/bin/grep -Fq -- "$needle" "$LAST_LOG"; then
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

      timing_test="$TMPDIR/update-usb-timing"
      mkdir -p "$timing_test"
      (
        # shellcheck disable=SC1091
        . "$update_usb_source_dir/phases.sh"
        TIMINGS=("Quick phase|59" "Opening LUKS|92" "Syncing squashfs to USB|780" "Full update|2243")
        print_timing_summary
      ) > "$timing_test/actual"

      cat > "$timing_test/expected" <<'EOF'
      === USB Update: Timing Summary ===
        - Quick phase: 59s
        - Opening LUKS: 1m 32s
        - Syncing squashfs to USB: 13m
        - Full update: 37m 23s
        - total: 52m 54s
      EOF
      if ! cmp -s "$timing_test/expected" "$timing_test/actual"; then
        echo "Expected update-usb timing summary to use human-readable durations." >&2
        echo "Expected:" >&2
        ${pkgs.gnused}/bin/sed 's/^/  /' "$timing_test/expected" >&2
        echo "Actual:" >&2
        ${pkgs.gnused}/bin/sed 's/^/  /' "$timing_test/actual" >&2
        exit 1
      fi

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

      if ! ${pkgs.gnugrep}/bin/grep -Fq "findmnt -Rrn --mountpoint" "$update_usb_source_dir/cleanup.sh"; then
        echo "Expected update-usb cleanup to unmount nested filesystems deepest-first." >&2
        ${pkgs.gnused}/bin/sed -n '1,140p' "$update_usb_source_dir/cleanup.sh" >&2
        exit 1
      fi

      metadata_test="$TMPDIR/update-usb-metadata"
      mkdir -p "$metadata_test/bin"
      {
        printf '%s\n' '#!${pkgs.bash}/bin/bash'
        printf '%s\n' 'echo "simulated nix eval failure" >&2'
        printf '%s\n' 'exit 42'
      } > "$metadata_test/bin/nix"
      chmod +x "$metadata_test/bin/nix"

      set +e
      (
        export PATH="$metadata_test/bin:$PATH"
        FLAKE_DIR=/fake-flake
        # shellcheck disable=SC1091
        . "$update_usb_source_dir/metadata.sh"
        capture_desired_system_metadata
      ) > "$metadata_test/capture.out" 2>"$metadata_test/capture.err"
      metadata_status=$?
      set -e

      if [ "$metadata_status" -eq 0 ]; then
        echo "Expected desired USB metadata capture to fail when toplevel evaluation fails." >&2
        ${pkgs.gnused}/bin/sed 's/^/  /' "$metadata_test/capture.out" >&2
        ${pkgs.gnused}/bin/sed 's/^/  /' "$metadata_test/capture.err" >&2
        exit 1
      fi

      if ! ${pkgs.gnugrep}/bin/grep -Fq "refusing to update USB before touching it" "$update_usb_source_dir/main.sh"; then
        echo "Expected update-usb to abort before touching the USB when desired toplevel evaluation fails." >&2
        ${pkgs.gnused}/bin/sed -n '80,120p' "$update_usb_source_dir/main.sh" >&2
        exit 1
      fi

      capture_line="$(${pkgs.gnugrep}/bin/grep -n 'capture_desired_system_metadata' "$update_usb_source_dir/main.sh" | ${pkgs.coreutils}/bin/cut -d: -f1 | ${pkgs.coreutils}/bin/head -n1)"
      luks_line="$(${pkgs.gnugrep}/bin/grep -n 'phase_begin "opening-luks"' "$update_usb_source_dir/main.sh" | ${pkgs.coreutils}/bin/cut -d: -f1 | ${pkgs.coreutils}/bin/head -n1)"
      if [ -z "$capture_line" ] || [ -z "$luks_line" ] || [ "$capture_line" -ge "$luks_line" ]; then
        echo "Expected update-usb to capture desired metadata before opening LUKS." >&2
        ${pkgs.gnused}/bin/sed -n '80,140p' "$update_usb_source_dir/main.sh" >&2
        exit 1
      fi

      cleanup_test="$TMPDIR/update-usb-cleanup"
      mkdir -p "$cleanup_test/bin"
      {
        printf '%s\n' '#!${pkgs.bash}/bin/bash'
        printf '%s\n' "printf '%s\\n' / /sys /run /nix/store /home/stefan/games /mnt /mnt/boot /mnt/nix/store"
      } > "$cleanup_test/bin/findmnt"
      chmod +x "$cleanup_test/bin/findmnt"

      {
        printf '%s\n' '#!${pkgs.bash}/bin/bash'
        printf '%s\n' '[ "$1" = "-q" ]'
      } > "$cleanup_test/bin/mountpoint"
      chmod +x "$cleanup_test/bin/mountpoint"

      {
        printf '%s\n' '#!${pkgs.bash}/bin/bash'
        printf '%s\n' 'echo "$1" >> "$CLEANUP_UMOUNT_LOG"'
      } > "$cleanup_test/bin/umount"
      chmod +x "$cleanup_test/bin/umount"

      export CLEANUP_UMOUNT_LOG="$cleanup_test/umount.log"
      : > "$CLEANUP_UMOUNT_LOG"
      (
        export PATH="$cleanup_test/bin:$PATH"
        MOUNT_POINT=/mnt
        # shellcheck disable=SC1091
        . "$update_usb_source_dir/cleanup.sh"
        cleanup_mount_tree
      )

      cat > "$cleanup_test/expected-umounts" <<'EOF'
      /mnt/nix/store
      /mnt/boot
      /mnt
      EOF
      if ! cmp -s "$cleanup_test/expected-umounts" "$CLEANUP_UMOUNT_LOG"; then
        echo "Expected update-usb cleanup to unmount only the /mnt mount tree." >&2
        echo "Expected:" >&2
        ${pkgs.gnused}/bin/sed 's/^/  /' "$cleanup_test/expected-umounts" >&2
        echo "Actual:" >&2
        ${pkgs.gnused}/bin/sed 's/^/  /' "$CLEANUP_UMOUNT_LOG" >&2
        exit 1
      fi

      for forbidden_cleanup_target in / /sys /run /nix/store /home/stefan/games; do
        if ${pkgs.gnugrep}/bin/grep -Fxq "$forbidden_cleanup_target" "$CLEANUP_UMOUNT_LOG"; then
          echo "update-usb cleanup attempted to unmount host path: $forbidden_cleanup_target" >&2
          ${pkgs.gnused}/bin/sed 's/^/  /' "$CLEANUP_UMOUNT_LOG" >&2
          exit 1
        fi
      done

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
      assert_log_contains "stop"
      assert_log_contains "--mic"

      run_expect 1 gsr-record-invalid-mode "$desktop_home/bin/gsr-record" nope
      assert_log_contains "Error: unknown mode 'nope'."

      stop_runtime="$TMPDIR/gsr-stop-runtime"
      run_expect 0 gsr-record-stop-empty env XDG_RUNTIME_DIR="$stop_runtime" HOME="$TMPDIR/gsr-stop-home" "$desktop_home/bin/gsr-record" stop
      assert_log_contains "No active recording."

      fake_runtime="$TMPDIR/gsr-fake-runtime"
      fake_home="$TMPDIR/gsr-fake-home"
      fake_bin="$TMPDIR/gsr-fake-bin"
      fake_log="$TMPDIR/gsr-fake-signal.log"
      mkdir -p "$fake_runtime/gsr-record" "$fake_home/videos/screencasts" "$fake_bin"
      cat > "$fake_bin/kill" <<SH
      #!${pkgs.bash}/bin/bash
      set -euo pipefail
      if [ "\$1" = "-INT" ]; then
        echo INT > "\$GSR_FAKE_SIGNAL_LOG"
        shift
        exec ${pkgs.procps}/bin/kill -INT "\$@"
      fi
      if [ "\$1" = "-0" ] && [ -f "\$GSR_FAKE_SIGNAL_LOG" ]; then
        exit 1
      fi
      exec ${pkgs.procps}/bin/kill "\$@"
      SH
      chmod +x "$fake_bin/kill"
      cat > "$fake_bin/gpu-screen-recorder" <<SH
      #!${pkgs.python3}/bin/python3
      import time

      while True:
          time.sleep(1)
      SH
      chmod +x "$fake_bin/gpu-screen-recorder"
      "$fake_bin/gpu-screen-recorder" &
      fake_pid=$!
      echo "$fake_pid" > "$fake_runtime/gsr-record/pid"
      echo "$fake_home/videos/screencasts/fake.mp4" > "$fake_runtime/gsr-record/outfile"
      echo recording > "$fake_runtime/gsr-record/status"
      run_expect 0 gsr-record-stop-fake env XDG_RUNTIME_DIR="$fake_runtime" HOME="$fake_home" GSR_RECORD_KILL="$fake_bin/kill" GSR_FAKE_SIGNAL_LOG="$fake_log" "$desktop_home/bin/gsr-record" stop
      assert_log_contains "Recorder stopped, but no file was saved."
      if [ "$(cat "$fake_log")" != "INT" ]; then
        echo "Expected gsr-record stop to send SIGINT to the active recorder." >&2
        exit 1
      fi
      if [ -e "$fake_runtime/gsr-record/pid" ] || [ -e "$fake_runtime/gsr-record/outfile" ] || [ -e "$fake_runtime/gsr-record/status" ]; then
        echo "Expected gsr-record stop to clear recorder state files." >&2
        find "$fake_runtime/gsr-record" -maxdepth 1 -type f -print >&2
        exit 1
      fi

      run_expect 1 gsr-record-invalid-option "$desktop_home/bin/gsr-record" fullscreen --bogus
      assert_log_contains "Error: unknown option --bogus."

      locked_runtime="$TMPDIR/gsr-locked-runtime"
      mkdir -p "$locked_runtime/gsr-record"
      exec 8>"$locked_runtime/gsr-record/lock"
      ${pkgs.util-linux}/bin/flock -n 8
      run_expect 1 gsr-record-selection-lock env XDG_RUNTIME_DIR="$locked_runtime" HOME="$TMPDIR/gsr-home" "$desktop_home/bin/gsr-record" region
      assert_log_contains "Selection or recorder state change already in progress."
      ${pkgs.util-linux}/bin/flock -u 8

      if ! ${pkgs.gnugrep}/bin/grep -Fq 'default_output|default_input' "$desktop_home/bin/gsr-record"; then
        echo "Expected gsr-record to support combined desktop and microphone audio." >&2
        ${pkgs.gnused}/bin/sed -n '1,240p' "$desktop_home/bin/gsr-record" >&2
        exit 1
      fi

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

      if ${pkgs.gnugrep}/bin/grep -Fq "DMS_FORCE_EXTWS=1" ${usbDmsServiceEnvironmentFile}; then
        echo "Expected USB DMS service to use Hyprland-native workspace state instead of forcing ext-workspace." >&2
        ${pkgs.gnused}/bin/sed 's/^/  /' ${usbDmsServiceEnvironmentFile} >&2
        exit 1
      fi

      if ! ${pkgs.gnugrep}/bin/grep -Fq "/bin/merge-codex-config" "$desktop_activation/activate"; then
        echo "Expected Home Manager activation to call the generated Codex config merger." >&2
        ${pkgs.gnused}/bin/sed -n '/ensureWritableCodexConfig/,/Activating/p' "$desktop_activation/activate" >&2
        exit 1
      fi

      if ! ${pkgs.gnugrep}/bin/grep -Fq "ensureWritableCodexDirectory" "$usb_activation/activate"; then
        echo "Expected USB Home Manager activation to repair a stale symlinked ~/.codex before link checks." >&2
        ${pkgs.gnused}/bin/sed -n '/ensureWritableCodexDirectory/,/Activating/p' "$usb_activation/activate" >&2
        exit 1
      fi

      codex_dir_line="$(${pkgs.gnugrep}/bin/grep -n 'Activating %s" "ensureWritableCodexDirectory' "$usb_activation/activate" | cut -d: -f1 | head -n1)"
      check_links_line="$(${pkgs.gnugrep}/bin/grep -n 'Activating %s" "checkLinkTargets' "$usb_activation/activate" | cut -d: -f1 | head -n1)"
      link_generation_line="$(${pkgs.gnugrep}/bin/grep -n 'Activating %s" "linkGeneration' "$usb_activation/activate" | cut -d: -f1 | head -n1)"
      codex_config_line="$(${pkgs.gnugrep}/bin/grep -n 'Activating %s" "ensureWritableCodexConfig' "$usb_activation/activate" | cut -d: -f1 | head -n1)"
      if [ -z "$codex_dir_line" ] || [ -z "$check_links_line" ] || [ "$codex_dir_line" -ge "$check_links_line" ]; then
        echo "Expected Codex directory repair to run before Home Manager link collision checks." >&2
        exit 1
      fi
      if [ -z "$link_generation_line" ] || [ -z "$codex_config_line" ] || [ "$codex_config_line" -le "$link_generation_line" ]; then
        echo "Expected Codex config merge to run after Home Manager creates declarative file links." >&2
        exit 1
      fi

      codex_seed_path="$(${pkgs.gnused}/bin/sed -n 's|.*merge-codex-config \(/nix/store/[^ ]*-codex-config.toml\) .*|\1|p' "$desktop_activation/activate" | head -n1)"
      if [ -z "$codex_seed_path" ] || [ ! -f "$codex_seed_path" ]; then
        echo "Expected Home Manager activation to reference the generated Codex seed config." >&2
        ${pkgs.gnused}/bin/sed -n '/ensureWritableCodexConfig/,/Activating/p' "$desktop_activation/activate" >&2
        exit 1
      fi

      assert_log_contains_file \
        "experimental_use_rmcp_client = true" \
        "$codex_seed_path" \
        "Expected Codex config to enable the remote MCP client required by Linear OAuth."

      assert_log_contains_file \
        'url = "https://mcp.linear.app/mcp"' \
        "$codex_seed_path" \
        "Expected Codex config to include the Linear MCP server."

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

      symlink_dir="$TMPDIR/codex/symlink"
      symlink_config="$symlink_dir/config.toml"
      mkdir -p "$symlink_dir"
      ln -s "$codex_seed_path" "$symlink_config"
      run_codex_merge "$symlink_config"
      ${codexConfigPython}/bin/python3 - "$symlink_config" <<'PY'
      import os
      from pathlib import Path
      import stat
      import sys
      import tomllib

      path = Path(sys.argv[1])
      assert not path.is_symlink()
      assert stat.S_IMODE(os.stat(path).st_mode) == 0o600
      with path.open("rb") as f:
          data = tomllib.load(f)
      assert data["model"] == "gpt-5.5"
      assert data["projects"]["/home/stefan/system-manifest"]["trust_level"] == "trusted"
      PY

      broken_symlink_dir="$TMPDIR/codex/broken-symlink"
      broken_symlink="$broken_symlink_dir/config.toml"
      mkdir -p "$broken_symlink_dir"
      ln -s "$TMPDIR/codex/missing-config.toml" "$broken_symlink"
      run_codex_merge "$broken_symlink"
      ${codexConfigPython}/bin/python3 - "$broken_symlink" <<'PY'
      from pathlib import Path
      import sys
      import tomllib

      path = Path(sys.argv[1])
      assert not path.is_symlink()
      with path.open("rb") as f:
          data = tomllib.load(f)
      assert data["model"] == "gpt-5.5"
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
