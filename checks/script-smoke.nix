{ctx}: let
  inherit
    (ctx)
    codexConfigPython
    desktopActivation
    desktopHome
    desktopZellijDevLayoutFile
    desktopZellijLegacyArgsScrubActivationFile
    desktopZellijPostCommandDiscoveryHook
    pkgs
    updateUsbSourceDir
    usbActivation
    usbDmsServiceEnvironmentFile
    usbHome
    usbHostScratchCheckpointExec
    usbHostScratchServiceDescriptionFile
    usbHostScratchShutdownCleanupScript
    usbHostScratchStartScript
    usbHostScratchStopScript
    usbHostScratchSyncScript
    usbShutdownRamfsStorePathsFile
    usbTmpfilesRulesFile
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
            desktop_zellij_legacy_args_scrub_activation="${desktopZellijLegacyArgsScrubActivationFile}"
            desktop_zellij_post_command_discovery_hook="${desktopZellijPostCommandDiscoveryHook}"
            update_usb_source_dir="${updateUsbSourceDir}"
            usb_activation="${usbActivation}"
            usb_home="${usbHome}"
            usb_host_scratch_description="${usbHostScratchServiceDescriptionFile}"
            usb_host_scratch_start="${usbHostScratchStartScript}"
            usb_host_scratch_shutdown_cleanup="${usbHostScratchShutdownCleanupScript}"
            usb_host_scratch_stop="${usbHostScratchStopScript}"
            usb_host_scratch_sync="${usbHostScratchSyncScript}"
            usb_host_scratch_checkpoint_exec="${usbHostScratchCheckpointExec}"
            usb_shutdown_ramfs_store_paths="${usbShutdownRamfsStorePathsFile}"
            usb_tmpfiles_rules="${usbTmpfilesRulesFile}"
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

            assert_log_not_contains() {
              local needle="$1"
              if ${pkgs.gnugrep}/bin/grep -Fq -- "$needle" "$LAST_LOG"; then
                echo "Expected not to find '$needle' in $LAST_LOG" >&2
                ${pkgs.gnused}/bin/sed 's/^/  /' "$LAST_LOG" >&2
                exit 1
              fi
            }

            run_expect 0 setup-persistent-usb-help "$usb_home/bin/setup-persistent-usb" --help
            assert_log_contains "Creates a fresh persistent NixOS USB"

            if ${pkgs.gnugrep}/bin/grep -Eq '^Prepare\b' "$usb_host_scratch_description"; then
              echo "Expected USB host scratch service description to read naturally during stop jobs." >&2
              ${pkgs.gnused}/bin/sed 's/^/  /' "$usb_host_scratch_description" >&2
              exit 1
            fi

            assert_file_contains() {
              local file="$1"
              local needle="$2"
              local message="$3"

              if ! ${pkgs.gnugrep}/bin/grep -Fq -- "$needle" "$file"; then
                echo "$message" >&2
                ${pkgs.gnused}/bin/sed 's/^/  /' "$file" >&2
                exit 1
              fi
            }

            assert_not_file_contains() {
              local file="$1"
              local needle="$2"
              local message="$3"

              if ${pkgs.gnugrep}/bin/grep -Fq -- "$needle" "$file"; then
                echo "$message" >&2
                ${pkgs.gnused}/bin/sed 's/^/  /' "$file" >&2
                exit 1
              fi
            }

            assert_file_contains "$usb_host_scratch_start" "mount --make-private" "Expected USB host scratch to preserve a private view of the underlying USB home."
            assert_file_contains "$usb_tmpfiles_rules" "d /run/usb-host-scratch 0700 root root" "Expected the private USB-home bind parent to remain root-only."
            assert_file_contains "$usb_host_scratch_stop" "shutdown sync failed" "Expected USB host scratch stop to report failed final synchronization."
            assert_file_contains "$usb_host_scratch_stop" "shutdown cleanup evidence" "Expected USB host scratch stop to preserve cleanup evidence after incomplete stops."
            assert_not_file_contains "$usb_host_scratch_stop" "umount -l" "Expected USB host scratch stop to avoid lazy-detaching live bind mounts."
            assert_file_contains "$usb_host_scratch_sync" '"$FLOCK" -x 9' "Expected USB host scratch synchronization to serialize checkpoints."
            assert_file_contains "$usb_host_scratch_sync" "Docker state and repositories remain temporary" "Expected USB host scratch synchronization to disclose excluded ephemeral data."
            assert_file_contains "$usb_host_scratch_checkpoint_exec" " checkpoint" "Expected the manual checkpoint unit to use the shared synchronization helper."
            assert_file_contains "$usb_host_scratch_shutdown_cleanup" 'close "$MAPPER_NAME"' "Expected shutdown cleanup to close the host scratch mapper."
            assert_file_contains "$usb_host_scratch_shutdown_cleanup" ".nixos-usb/session" "Expected shutdown cleanup to remove host-side encrypted scratch sessions."
            assert_file_contains "$usb_host_scratch_shutdown_cleanup" "unmount_tree" "Expected shutdown cleanup to unmount scratch mount trees explicitly."
            assert_file_contains "$usb_host_scratch_shutdown_cleanup" "trying lazy unmount" "Expected shutdown cleanup to lazily unmount stuck scratch mounts."
            assert_not_file_contains "$usb_host_scratch_shutdown_cleanup" ":-/bin/findmnt" "Expected shutdown cleanup findmnt default to use a copied store path."
            assert_not_file_contains "$usb_host_scratch_shutdown_cleanup" ":-/bin/umount" "Expected shutdown cleanup umount default to use a copied store path."
            assert_not_file_contains "$usb_host_scratch_shutdown_cleanup" ":-/bin/cryptsetup" "Expected shutdown cleanup cryptsetup default to use a copied store path."
            assert_not_file_contains "$usb_host_scratch_shutdown_cleanup" ":-/bin/grep" "Expected shutdown cleanup grep default to use a copied store path."
            assert_file_contains "$usb_host_scratch_shutdown_cleanup" "util-linux" "Expected shutdown cleanup to reference util-linux store paths."
            assert_file_contains "$usb_host_scratch_shutdown_cleanup" "gnugrep" "Expected shutdown cleanup to reference gnugrep store paths."
            assert_file_contains "$usb_shutdown_ramfs_store_paths" "util-linux" "Expected shutdown ramfs to include util-linux tools."
            assert_file_contains "$usb_shutdown_ramfs_store_paths" "cryptsetup" "Expected shutdown ramfs to include cryptsetup."
            assert_file_contains "$usb_shutdown_ramfs_store_paths" "gnugrep" "Expected shutdown ramfs to include gnugrep."
            assert_file_contains "$usb_home/bin/nixos-usb-store-status" "== /nix mount tree ==" "Expected USB store status to print mount topology."
            assert_file_contains "$usb_home/bin/nixos-usb-store-status" "findmnt -R /nix" "Expected USB store status to collect the /nix mount tree."
            assert_file_contains "$usb_home/bin/nixos-usb-store-status" "cmd_age=300s" "Expected USB store status to flag 300 second USB storage timeouts."
            assert_file_contains "$usb_home/bin/nixos-usb-store-status" "Maybe the USB cable is bad?" "Expected USB store status to explain kernel USB transport warnings."
            assert_file_contains "$usb_home/bin/usb-host-scratch" "checkpoint)" "Expected usb-host-scratch to expose a manual checkpoint command."
            assert_file_contains "$usb_home/bin/usb-host-scratch" "repositories remain temporary" "Expected checkpoint output to warn about temporary repositories."

            host_scratch_sync_test="$TMPDIR/usb-host-scratch-sync"
            mkdir -p \
              "$host_scratch_sync_test/user/cache" \
              "$host_scratch_sync_test/user/codex" \
              "$host_scratch_sync_test/user/brave-config" \
              "$host_scratch_sync_test/usb/.cache" \
              "$host_scratch_sync_test/usb/.codex" \
              "$host_scratch_sync_test/usb/.config" \
              "$host_scratch_sync_test/usb/.config/BraveSoftware" \
              "$host_scratch_sync_test/run" \
              "$host_scratch_sync_test/bin"
            printf '%s\n' cache-current > "$host_scratch_sync_test/user/cache/current"
            printf '%s\n' codex-current > "$host_scratch_sync_test/user/codex/current"
            printf '%s\n' brave-current > "$host_scratch_sync_test/user/brave-config/current"
            touch "$host_scratch_sync_test/usb/.cache/stale"
            printf '%s\n' encrypted-host-scratch > "$host_scratch_sync_test/mode"

            cat > "$host_scratch_sync_test/bin/findmnt" <<'EOF'
      #!${pkgs.bash}/bin/bash
      set -eu
      [ "$1" = "-rn" ]
      [ "$2" = "-M" ]
      [ "$3" = "$USB_HOST_SCRATCH_TEST_USB_HOME" ]
      EOF
            chmod +x "$host_scratch_sync_test/bin/findmnt"
            cat > "$host_scratch_sync_test/bin/chown" <<'EOF'
      #!${pkgs.bash}/bin/bash
      set -eu
      printf '%s\n' "$*" >> "$USB_HOST_SCRATCH_TEST_CHOWN_LOG"
      EOF
            chmod +x "$host_scratch_sync_test/bin/chown"
            : > "$host_scratch_sync_test/chown.log"

            run_expect 0 host-scratch-sync-helper \
              env \
                USB_HOST_SCRATCH_MODE_FILE="$host_scratch_sync_test/mode" \
                USB_HOST_SCRATCH_STATE_DIR="$host_scratch_sync_test/run" \
                USB_HOST_SCRATCH_ATTEMPT_STATE="$host_scratch_sync_test/last-attempt" \
                USB_HOST_SCRATCH_USB_HOME="$host_scratch_sync_test/usb" \
                USB_HOST_SCRATCH_USER_ROOT="$host_scratch_sync_test/user" \
                USB_HOST_SCRATCH_LAST_SYNC_STATE="$host_scratch_sync_test/usb/.local/state/system-manifest/host-scratch-last-sync" \
                USB_HOST_SCRATCH_FINDMNT="$host_scratch_sync_test/bin/findmnt" \
                USB_HOST_SCRATCH_CHOWN="$host_scratch_sync_test/bin/chown" \
                USB_HOST_SCRATCH_SYNC="${pkgs.coreutils}/bin/true" \
                USB_HOST_SCRATCH_TEST_CHOWN_LOG="$host_scratch_sync_test/chown.log" \
                USB_HOST_SCRATCH_TEST_USB_HOME="$host_scratch_sync_test/usb" \
                "$usb_host_scratch_sync" checkpoint
            assert_log_contains "checkpoint complete"
            assert_log_contains "repositories remain temporary"

            for synced_path in \
              .cache/current \
              .codex/current \
              .config/BraveSoftware/current; do
              if [ ! -f "$host_scratch_sync_test/usb/$synced_path" ]; then
                echo "Expected checkpoint to persist $synced_path to USB." >&2
                exit 1
              fi
            done
            if [ -e "$host_scratch_sync_test/usb/.cache/stale" ]; then
              echo "Expected checkpoint to mirror scratch cache deletions to USB." >&2
              exit 1
            fi
            last_sync_record="$host_scratch_sync_test/usb/.local/state/system-manifest/host-scratch-last-sync"
            assert_file_contains "$last_sync_record" "result=success" "Expected checkpoint to record its last successful sync."
            assert_file_contains "$last_sync_record" "targets=cache,codex,brave" "Expected checkpoint status to identify persistent targets."
            assert_file_contains "$last_sync_record" "excluded=docker,repositories" "Expected checkpoint status to record excluded temporary data."
            assert_file_contains "$host_scratch_sync_test/last-attempt" "result=success" "Expected public runtime status to show the latest checkpoint result."
            for user_owned_path in \
              "$host_scratch_sync_test/usb/.cache" \
              "$host_scratch_sync_test/usb/.codex" \
              "$host_scratch_sync_test/usb/.config/BraveSoftware" \
              "$host_scratch_sync_test/usb/.local" \
              "$host_scratch_sync_test/usb/.local/state" \
              "$host_scratch_sync_test/usb/.local/state/system-manifest" \
              "$last_sync_record"; do
              if ! ${pkgs.gnugrep}/bin/grep -Fxq "stefan:users $user_owned_path" "$host_scratch_sync_test/chown.log"; then
                echo "Expected checkpoint to leave user state owned by stefan:users: $user_owned_path" >&2
                ${pkgs.gnused}/bin/sed 's/^/  /' "$host_scratch_sync_test/chown.log" >&2
                exit 1
              fi
            done

            rm -rf "$host_scratch_sync_test/user/brave-config"
            run_expect 1 host-scratch-sync-helper-failure \
              env \
                USB_HOST_SCRATCH_MODE_FILE="$host_scratch_sync_test/mode" \
                USB_HOST_SCRATCH_STATE_DIR="$host_scratch_sync_test/run" \
                USB_HOST_SCRATCH_ATTEMPT_STATE="$host_scratch_sync_test/last-attempt" \
                USB_HOST_SCRATCH_USB_HOME="$host_scratch_sync_test/usb" \
                USB_HOST_SCRATCH_USER_ROOT="$host_scratch_sync_test/user" \
                USB_HOST_SCRATCH_LAST_SYNC_STATE="$last_sync_record" \
                USB_HOST_SCRATCH_FINDMNT="$host_scratch_sync_test/bin/findmnt" \
                USB_HOST_SCRATCH_CHOWN="$host_scratch_sync_test/bin/chown" \
                USB_HOST_SCRATCH_SYNC="${pkgs.coreutils}/bin/true" \
                USB_HOST_SCRATCH_TEST_CHOWN_LOG="$host_scratch_sync_test/chown.log" \
                USB_HOST_SCRATCH_TEST_USB_HOME="$host_scratch_sync_test/usb" \
                "$usb_host_scratch_sync" checkpoint
            assert_log_contains "USB state may be stale"
            assert_file_contains "$host_scratch_sync_test/last-attempt" "result=failed" "Expected public runtime status to expose a failed checkpoint."
            assert_file_contains "$last_sync_record" "result=success" "Expected a failed checkpoint to preserve the last successful sync record."

            cat > "$host_scratch_sync_test/bin/id" <<'EOF'
      #!${pkgs.bash}/bin/bash
      set -eu
      [ "$1" = "-u" ]
      printf '%s\n' 1000
      EOF
            chmod +x "$host_scratch_sync_test/bin/id"
            cat > "$host_scratch_sync_test/bin/sudo" <<'EOF'
      #!${pkgs.bash}/bin/bash
      set -eu
      printf '%s\n' "$*" > "$USB_HOST_SCRATCH_TEST_SUDO_LOG"
      EOF
            chmod +x "$host_scratch_sync_test/bin/sudo"

            run_expect 0 host-scratch-checkpoint-command \
              env \
                USB_HOST_SCRATCH_MODE_FILE="$host_scratch_sync_test/mode" \
                USB_HOST_SCRATCH_ID="$host_scratch_sync_test/bin/id" \
                USB_HOST_SCRATCH_SUDO="$host_scratch_sync_test/bin/sudo" \
                USB_HOST_SCRATCH_SYSTEMCTL="$host_scratch_sync_test/bin/systemctl" \
                USB_HOST_SCRATCH_TEST_SUDO_LOG="$host_scratch_sync_test/sudo.log" \
                "$usb_home/bin/usb-host-scratch" checkpoint
            assert_log_contains "Docker state and repositories remain temporary"
            if ! ${pkgs.gnugrep}/bin/grep -Fxq "$host_scratch_sync_test/bin/systemctl start --wait usb-host-scratch-checkpoint.service" "$host_scratch_sync_test/sudo.log"; then
              echo "Expected usb-host-scratch checkpoint to start the checkpoint system unit." >&2
              ${pkgs.gnused}/bin/sed 's/^/  /' "$host_scratch_sync_test/sudo.log" >&2
              exit 1
            fi

            host_scratch_cleanup_test="$TMPDIR/usb-host-scratch-cleanup"
            mkdir -p "$host_scratch_cleanup_test/bin" "$host_scratch_cleanup_test/root/nix/.host-store/.nixos-usb/session/boot-id"
            touch "$host_scratch_cleanup_test/mapper"
            cat > "$host_scratch_cleanup_test/mounted" <<EOF
            $host_scratch_cleanup_test/root/nix/store
            $host_scratch_cleanup_test/root/nix/.rw-store
            $host_scratch_cleanup_test/root/nix/.ro-store
            $host_scratch_cleanup_test/root/nix/.host-store-rw
            $host_scratch_cleanup_test/root/nix/.host-scratch
            $host_scratch_cleanup_test/root/nix/.host-store
            EOF

            cat > "$host_scratch_cleanup_test/bin/findmnt" <<'EOF'
            #!${pkgs.bash}/bin/bash
            set -euo pipefail

            mounted_file="$USB_HOST_SCRATCH_TEST_MOUNTED"
            case "$1 $2" in
              "-rn -M")
                ${pkgs.gnugrep}/bin/grep -Fxq "$3" "$mounted_file"
                ;;
              "-Rrn --target")
                target="$3"
                ${pkgs.gawk}/bin/awk -v target="$target" '$0 == target || index($0, target "/") == 1 { print }' "$mounted_file"
                ;;
              *)
                echo "unexpected findmnt args: $*" >&2
                exit 2
                ;;
            esac
            EOF
            chmod +x "$host_scratch_cleanup_test/bin/findmnt"

            cat > "$host_scratch_cleanup_test/bin/umount" <<'EOF'
            #!${pkgs.bash}/bin/bash
            set -euo pipefail

            mounted_file="$USB_HOST_SCRATCH_TEST_MOUNTED"
            log_file="$USB_HOST_SCRATCH_TEST_UMOUNT_LOG"
            mode=normal
            target="$1"
            if [ "$1" = "-l" ]; then
              mode=lazy
              target="$2"
            fi
            printf '%s %s\n' "$mode" "$target" >> "$log_file"
            if [ "$mode" = normal ] && [ "$target" = "$USB_HOST_SCRATCH_TEST_FAIL_NORMAL_TARGET" ]; then
              exit 1
            fi
            ${pkgs.gnugrep}/bin/grep -Fxv "$target" "$mounted_file" > "$mounted_file.tmp" || true
            ${pkgs.coreutils}/bin/mv "$mounted_file.tmp" "$mounted_file"
            EOF
            chmod +x "$host_scratch_cleanup_test/bin/umount"

            cat > "$host_scratch_cleanup_test/bin/cryptsetup" <<'EOF'
            #!${pkgs.bash}/bin/bash
            set -euo pipefail
            printf '%s\n' "$*" >> "$USB_HOST_SCRATCH_TEST_CRYPT_LOG"
            EOF
            chmod +x "$host_scratch_cleanup_test/bin/cryptsetup"

            cat > "$host_scratch_cleanup_test/bin/rm" <<'EOF'
            #!${pkgs.bash}/bin/bash
            set -euo pipefail
            printf '%s\n' "$*" >> "$USB_HOST_SCRATCH_TEST_RM_LOG"
            exec ${pkgs.coreutils}/bin/rm "$@"
            EOF
            chmod +x "$host_scratch_cleanup_test/bin/rm"

            : > "$host_scratch_cleanup_test/umount.log"
            : > "$host_scratch_cleanup_test/crypt.log"
            : > "$host_scratch_cleanup_test/rm.log"
            env \
              USB_HOST_SCRATCH_FINDMNT="$host_scratch_cleanup_test/bin/findmnt" \
              USB_HOST_SCRATCH_UMOUNT="$host_scratch_cleanup_test/bin/umount" \
              USB_HOST_SCRATCH_CRYPTSETUP="$host_scratch_cleanup_test/bin/cryptsetup" \
              USB_HOST_SCRATCH_RM="$host_scratch_cleanup_test/bin/rm" \
              USB_HOST_SCRATCH_CHMOD="${pkgs.coreutils}/bin/chmod" \
              USB_HOST_SCRATCH_SORT="${pkgs.coreutils}/bin/sort" \
              USB_HOST_SCRATCH_GREP="${pkgs.gnugrep}/bin/grep" \
              USB_HOST_SCRATCH_MAPPER_DEVICE="$host_scratch_cleanup_test/mapper" \
              USB_HOST_SCRATCH_PREFIXES="$host_scratch_cleanup_test/root" \
              USB_HOST_SCRATCH_TEST_MOUNTED="$host_scratch_cleanup_test/mounted" \
              USB_HOST_SCRATCH_TEST_UMOUNT_LOG="$host_scratch_cleanup_test/umount.log" \
              USB_HOST_SCRATCH_TEST_CRYPT_LOG="$host_scratch_cleanup_test/crypt.log" \
              USB_HOST_SCRATCH_TEST_RM_LOG="$host_scratch_cleanup_test/rm.log" \
              USB_HOST_SCRATCH_TEST_FAIL_NORMAL_TARGET="$host_scratch_cleanup_test/root/nix/.host-scratch" \
              "$usb_host_scratch_shutdown_cleanup"

            cat > "$host_scratch_cleanup_test/expected-umounts" <<EOF
            normal $host_scratch_cleanup_test/root/nix/store
            normal $host_scratch_cleanup_test/root/nix/.rw-store
            normal $host_scratch_cleanup_test/root/nix/.ro-store
            normal $host_scratch_cleanup_test/root/nix/.host-store-rw
            normal $host_scratch_cleanup_test/root/nix/.host-scratch
            lazy $host_scratch_cleanup_test/root/nix/.host-scratch
            normal $host_scratch_cleanup_test/root/nix/.host-store
            EOF
            if ! cmp -s "$host_scratch_cleanup_test/expected-umounts" "$host_scratch_cleanup_test/umount.log"; then
              echo "Expected USB host scratch shutdown cleanup to unmount paths deepest-first with lazy fallback." >&2
              echo "Expected:" >&2
              ${pkgs.gnused}/bin/sed 's/^/  /' "$host_scratch_cleanup_test/expected-umounts" >&2
              echo "Actual:" >&2
              ${pkgs.gnused}/bin/sed 's/^/  /' "$host_scratch_cleanup_test/umount.log" >&2
              exit 1
            fi

            if ! ${pkgs.gnugrep}/bin/grep -Fxq "close nixos-usb-host-scratch" "$host_scratch_cleanup_test/crypt.log"; then
              echo "Expected USB host scratch shutdown cleanup to close the scratch mapper." >&2
              ${pkgs.gnused}/bin/sed 's/^/  /' "$host_scratch_cleanup_test/crypt.log" >&2
              exit 1
            fi

            if [ -d "$host_scratch_cleanup_test/root/nix/.host-store/.nixos-usb/session" ]; then
              echo "Expected USB host scratch shutdown cleanup to remove host session files." >&2
              exit 1
            fi

            run_expect 1 update-usb-removed-mode "$desktop_home/bin/update-usb" --mode nope
            assert_log_contains "Error: unknown option '--mode'."

            run_expect 0 update-usb-help "$desktop_home/bin/update-usb" --help
            assert_log_contains "sudo update-usb [-v|--verbose] [--in-place] [--force] [path-to-flake-dir]"
            assert_log_not_contains "--mode"

            args_test="$TMPDIR/update-usb-args"
            mkdir -p "$args_test"
            (
              DEFAULT_MODE=prebuild
              MODE="$DEFAULT_MODE"
              VERBOSE=0
              FORCE_UPDATE=0
              FLAKE_DIR=/start
              USB_ROOT_PART=/dev/root
              USB_BOOT_DEV=/dev/boot
              # shellcheck disable=SC1091
              . "$update_usb_source_dir/args.sh"
              parse_args -v --in-place --force /flake
              printf 'mode=%s\nverbose=%s\nforce=%s\nflake=%s\n' "$MODE" "$VERBOSE" "$FORCE_UPDATE" "$FLAKE_DIR"
            ) > "$args_test/short-verbose"
            cat > "$args_test/expected-short-verbose" <<'EOF'
            mode=in-place
            verbose=1
            force=1
            flake=/flake
            EOF
            if ! cmp -s "$args_test/expected-short-verbose" "$args_test/short-verbose"; then
              echo "Expected update-usb parser to handle -v, --in-place, and --force." >&2
              ${pkgs.gnused}/bin/sed 's/^/  /' "$args_test/short-verbose" >&2
              exit 1
            fi

            (
              DEFAULT_MODE=prebuild
              MODE="$DEFAULT_MODE"
              VERBOSE=0
              FORCE_UPDATE=0
              FLAKE_DIR=/start
              USB_ROOT_PART=/dev/root
              USB_BOOT_DEV=/dev/boot
              # shellcheck disable=SC1091
              . "$update_usb_source_dir/args.sh"
              parse_args --verbose /flake
              printf 'mode=%s\nverbose=%s\nforce=%s\nflake=%s\n' "$MODE" "$VERBOSE" "$FORCE_UPDATE" "$FLAKE_DIR"
            ) > "$args_test/long-verbose"
            cat > "$args_test/expected-long-verbose" <<'EOF'
            mode=prebuild
            verbose=1
            force=0
            flake=/flake
            EOF
            if ! cmp -s "$args_test/expected-long-verbose" "$args_test/long-verbose"; then
              echo "Expected update-usb parser to handle --verbose." >&2
              ${pkgs.gnused}/bin/sed 's/^/  /' "$args_test/long-verbose" >&2
              exit 1
            fi

            progress_test="$TMPDIR/update-usb-progress"
            mkdir -p "$progress_test"
            (
              # shellcheck disable=SC1091
              . "$update_usb_source_dir/phases.sh"
              progress_set 12 "Opening LUKS"
              progress_set 12 "Opening LUKS"
              progress_set 67 "Building squashfs"
              progress_set 66 "Building squashfs"
              map_percent_range 50 66 78
              adaptive_progress_end 6 1080 2260
              estimated_progress_percent 0 1080 6 50
              estimated_progress_percent 60 1080 6 50
              estimated_progress_percent 120 1080 6 50
              adaptive_progress_end 10 120 1180
              map_percent_range 50 43 98
              adaptive_progress_end 98 5 5
              adaptive_progress_end 98 1 1000
            ) > "$progress_test/actual"
            cat > "$progress_test/expected" <<'EOF'
            [12%] Opening LUKS
            [67%] Building squashfs
            72
            50
            6
            8
            10
            19
            70
            99
            99
            EOF
            if ! cmp -s "$progress_test/expected" "$progress_test/actual"; then
              echo "Expected update-usb progress helpers to emit concise percent lines." >&2
              ${pkgs.gnused}/bin/sed 's/^/  /' "$progress_test/actual" >&2
              exit 1
            fi

            if ${pkgs.gnugrep}/bin/grep -Fq "Still running" "$update_usb_source_dir/phases.sh"; then
              echo "Expected update-usb progress output to avoid generic still-running messages." >&2
              ${pkgs.gnused}/bin/sed -n '1,140p' "$update_usb_source_dir/phases.sh" >&2
              exit 1
            fi

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

            deferred_close_test="$TMPDIR/update-usb-deferred-close"
            mkdir -p "$deferred_close_test/bin"
            cat > "$deferred_close_test/bin/cryptsetup" <<'EOF'
            #!${pkgs.bash}/bin/bash
            case "$*" in
              "close NIXOS_USB_CRYPT")
                exit 1
                ;;
              "close --deferred NIXOS_USB_CRYPT")
                exit 0
                ;;
              *)
                echo "unexpected cryptsetup args: $*" >&2
                exit 2
                ;;
            esac
            EOF
            chmod +x "$deferred_close_test/bin/cryptsetup"

            cat > "$deferred_close_test/bin/findmnt" <<'EOF'
            #!${pkgs.bash}/bin/bash
            exit 1
            EOF
            chmod +x "$deferred_close_test/bin/findmnt"

            cat > "$deferred_close_test/bin/sleep" <<'EOF'
            #!${pkgs.bash}/bin/bash
            exit 0
            EOF
            chmod +x "$deferred_close_test/bin/sleep"

            (
              export PATH="$deferred_close_test/bin:$PATH"
              VERBOSE=0
              USB_MAPPER_NAME=NIXOS_USB_CRYPT
              MOUNT_POINT=/mnt
              # shellcheck disable=SC1091
              . "$update_usb_source_dir/phases.sh"
              # shellcheck disable=SC1091
              . "$update_usb_source_dir/cleanup.sh"
              close_usb_mapper
            ) > "$deferred_close_test/quiet.out" 2>&1
            if ${pkgs.gnugrep}/bin/grep -Fq "Deferred mapper close scheduled" "$deferred_close_test/quiet.out"; then
              echo "Expected quiet update-usb cleanup to hide deferred mapper close detail." >&2
              ${pkgs.gnused}/bin/sed 's/^/  /' "$deferred_close_test/quiet.out" >&2
              exit 1
            fi

            (
              export PATH="$deferred_close_test/bin:$PATH"
              VERBOSE=1
              USB_MAPPER_NAME=NIXOS_USB_CRYPT
              MOUNT_POINT=/mnt
              # shellcheck disable=SC1091
              . "$update_usb_source_dir/phases.sh"
              # shellcheck disable=SC1091
              . "$update_usb_source_dir/cleanup.sh"
              close_usb_mapper
            ) > "$deferred_close_test/verbose.out" 2>&1
            if ! ${pkgs.gnugrep}/bin/grep -Fq "Deferred mapper close scheduled for NIXOS_USB_CRYPT." "$deferred_close_test/verbose.out"; then
              echo "Expected verbose update-usb cleanup to show deferred mapper close detail." >&2
              ${pkgs.gnused}/bin/sed 's/^/  /' "$deferred_close_test/verbose.out" >&2
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

            if ! ${pkgs.gnugrep}/bin/grep -Fq 'nix build --no-link "$FLAKE_DIR#nixosConfigurations.usb.config.system.build.toplevel"' "$update_usb_source_dir/main.sh"; then
              echo "Expected update-usb to prebuild the USB system before nixos-install." >&2
              ${pkgs.gnused}/bin/sed -n '170,190p' "$update_usb_source_dir/main.sh" >&2
              exit 1
            fi

            if ! ${pkgs.gnugrep}/bin/grep -Fq 'nixos-install --system "$DESIRED_SYSTEM_TOPLEVEL"' "$update_usb_source_dir/main.sh"; then
              echo "Expected update-usb to install the prebuilt USB system path." >&2
              ${pkgs.gnused}/bin/sed -n '175,195p' "$update_usb_source_dir/main.sh" >&2
              exit 1
            fi

            if ${pkgs.gnugrep}/bin/grep -Fq 'nixos-install --flake' "$update_usb_source_dir/main.sh"; then
              echo "Expected update-usb not to hide flake builds inside nixos-install." >&2
              ${pkgs.gnused}/bin/sed -n '175,195p' "$update_usb_source_dir/main.sh" >&2
              exit 1
            fi

            if ! ${pkgs.gnugrep}/bin/grep -Fq 'run_logged_progress "Building squashfs"' "$update_usb_source_dir/main.sh"; then
              echo "Expected update-usb to route mksquashfs output through percent progress logging." >&2
              ${pkgs.gnused}/bin/sed -n '205,245p' "$update_usb_source_dir/main.sh" >&2
              exit 1
            fi

            for expected_progress_call in \
              'phase_begin "opening-luks" "Opening LUKS" 0' \
              'phase_begin "preparing-prebuild-stage" "Preparing local prebuild stage" 5' \
              'progress_plan_init 1080 120 10 5 10 360 660 10 5' \
              'phase_begin_estimated "building-usb-system" "Building USB system" 1080 6' \
              'phase_begin_estimated "installing-nixos" "Installing NixOS" 120' \
              'phase_begin_estimated "building-squashfs" "Building squashfs locally (desktop SSD)" 360' \
              'phase_begin_estimated "syncing-squashfs" "Syncing squashfs to USB" 660' \
              'copy_with_progress "$LOCAL_SQUASHFS" "$MOUNT_POINT/nix-store.squashfs.tmp" "$PHASE_PROGRESS_START" "$PHASE_PROGRESS_END"'; do
              if ! ${pkgs.gnugrep}/bin/grep -Fq "$expected_progress_call" "$update_usb_source_dir/main.sh"; then
                echo "Expected update-usb to use adaptive prebuild progress ranges: $expected_progress_call" >&2
                ${pkgs.gnused}/bin/sed -n '125,270p' "$update_usb_source_dir/main.sh" >&2
                exit 1
              fi
            done

            if ! ${pkgs.gnugrep}/bin/grep -Fq 'copy_with_progress "$LOCAL_SQUASHFS"' "$update_usb_source_dir/main.sh"; then
              echo "Expected update-usb to show byte-based progress while copying squashfs to USB." >&2
              ${pkgs.gnused}/bin/sed -n '220,235p' "$update_usb_source_dir/main.sh" >&2
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

            expected_codex_resurrect="${pkgs.bashInteractive}/bin/bash -lc 'exec codex'"
            for legacy_mcp_command in \
              'npm exec @upstash/context7-mcp --api-key legacy-secret' \
              '/nix/store/node/bin/npm exec @softeria/ms-365-mcp-server@0.126.0 --preset mail'; do
              actual_resurrect="$(env RESURRECT_COMMAND="$legacy_mcp_command" "$desktop_zellij_post_command_discovery_hook")"
              if [ "$actual_resurrect" != "$expected_codex_resurrect" ]; then
                echo "Expected Zellij command discovery hook to replace a known MCP descendant with Codex." >&2
                printf '  %s\n' "$actual_resurrect" >&2
                exit 1
              fi
            done

            unrelated_resurrect_command='npm exec @example/other-mcp --read-only'
            actual_resurrect="$(env RESURRECT_COMMAND="$unrelated_resurrect_command" "$desktop_zellij_post_command_discovery_hook")"
            if [ "$actual_resurrect" != "$unrelated_resurrect_command" ]; then
              echo "Expected Zellij command discovery hook to preserve unrelated commands." >&2
              printf '  %s\n' "$actual_resurrect" >&2
              exit 1
            fi

            zellij_sessionizer_test="$TMPDIR/zellij-sessionizer"
            mkdir -p "$zellij_sessionizer_test/bin" "$zellij_sessionizer_test/home/sortable"
            cat > "$zellij_sessionizer_test/bin/zellij" <<'EOF'
            #!${pkgs.bash}/bin/bash
            set -euo pipefail

            printf '%s\n' "$*" >> "$ZELLIJ_SESSIONIZER_TEST_LOG"
            case "$1" in
              list-sessions)
                if [ "$*" != "list-sessions --no-formatting" ]; then
                  echo "Expected an unformatted session listing, got: $*" >&2
                  exit 2
                fi
                case "$ZELLIJ_SESSIONIZER_TEST_STATE" in
                  live)
                    printf 'sortable [Created 1h ago]\n'
                    ;;
                  healthy-exited|corrupt-exited)
                    printf 'sortable [Created 1h ago] (EXITED - attach to resurrect)\n'
                    ;;
                  absent)
                    exit 1
                    ;;
                esac
                ;;
              attach)
                shift
                create=0
                forget=0
                session_name=
                for arg in "$@"; do
                  case "$arg" in
                    -c|--create)
                      create=1
                      ;;
                    --forget)
                      forget=1
                      ;;
                    -*)
                      ;;
                    *)
                      session_name="$arg"
                      ;;
                  esac
                done

                case "$ZELLIJ_SESSIONIZER_TEST_STATE" in
                  live)
                    if [ "$create" -eq 0 ] && [ "$forget" -eq 0 ] && [ "$session_name" = sortable ]; then
                      exit 0
                    fi
                    ;;
                  absent)
                    if [ "$create" -eq 1 ] && [ "$forget" -eq 0 ] && [ "$session_name" = sortable ]; then
                      exit 0
                    fi
                    ;;
                  healthy-exited)
                    if [ "$create" -eq 0 ] && [ "$forget" -eq 0 ] && [ "$session_name" = sortable ]; then
                      exit 0
                    fi
                    ;;
                  corrupt-exited)
                    if [ "$create" -eq 1 ] && [ "$forget" -eq 1 ] && [ "$session_name" = sortable ]; then
                      exit 0
                    fi
                    echo 'npm warn Unknown cli config "--api-key".' >&2
                    echo 'error: too many arguments. Expected 0 arguments but got 1.' >&2
                    ;;
                esac

                echo "Unexpected attach command for $ZELLIJ_SESSIONIZER_TEST_STATE session: attach $*" >&2
                exit 2
                ;;
              *)
                echo "Unexpected zellij invocation: $*" >&2
                exit 2
                ;;
            esac
            EOF
            chmod +x "$zellij_sessionizer_test/bin/zellij"
            zellij_sessionizer_cache="$zellij_sessionizer_test/cache"
            : > "$zellij_sessionizer_test/zellij.log"

            run_expect 0 zellij-sessionizer-live-session env -u ZELLIJ \
              HOME="$zellij_sessionizer_test/home" \
              PATH="$zellij_sessionizer_test/bin:$PATH" \
              XDG_CACHE_HOME="$zellij_sessionizer_cache" \
              ZELLIJ_SESSIONIZER_TEST_LOG="$zellij_sessionizer_test/zellij.log" \
              ZELLIJ_SESSIONIZER_TEST_STATE=live \
              "$desktop_home/bin/zellij-sessionizer" "$zellij_sessionizer_test/home/sortable"

            run_expect 0 zellij-sessionizer-absent-session env -u ZELLIJ \
              HOME="$zellij_sessionizer_test/home" \
              PATH="$zellij_sessionizer_test/bin:$PATH" \
              XDG_CACHE_HOME="$zellij_sessionizer_cache" \
              ZELLIJ_SESSIONIZER_TEST_LOG="$zellij_sessionizer_test/zellij.log" \
              ZELLIJ_SESSIONIZER_TEST_STATE=absent \
              "$desktop_home/bin/zellij-sessionizer" "$zellij_sessionizer_test/home/sortable"

            session_layout_dir="$zellij_sessionizer_cache/zellij/contract_version_1/session_info/sortable"
            mkdir -p "$session_layout_dir"
            cat > "$session_layout_dir/session-layout.kdl" <<'EOF'
            layout {
                pane command="npm" name="unrelated" {
                    args "exec" "@example/other-mcp"
                }
                pane command="/nix/store/bash/bin/bash" name="context-note" {
                    args "exec" "@upstash/context7-mcp"
                }
            }
            EOF

            run_expect 0 zellij-sessionizer-healthy-exited-session env -u ZELLIJ \
              HOME="$zellij_sessionizer_test/home" \
              PATH="$zellij_sessionizer_test/bin:$PATH" \
              XDG_CACHE_HOME="$zellij_sessionizer_cache" \
              ZELLIJ_SESSIONIZER_TEST_LOG="$zellij_sessionizer_test/zellij.log" \
              ZELLIJ_SESSIONIZER_TEST_STATE=healthy-exited \
              "$desktop_home/bin/zellij-sessionizer" "$zellij_sessionizer_test/home/sortable"

            cat > "$session_layout_dir/session-layout.kdl" <<'EOF'
            layout {
                pane command="npm" {
                    args "exec" "@softeria/ms-365-mcp-server@0.126.0" "--preset" "mail"
                }
            }
            EOF

            run_expect 0 zellij-sessionizer-corrupt-exited-session env -u ZELLIJ \
              HOME="$zellij_sessionizer_test/home" \
              PATH="$zellij_sessionizer_test/bin:$PATH" \
              XDG_CACHE_HOME="$zellij_sessionizer_cache" \
              ZELLIJ_SESSIONIZER_TEST_LOG="$zellij_sessionizer_test/zellij.log" \
              ZELLIJ_SESSIONIZER_TEST_STATE=corrupt-exited \
              "$desktop_home/bin/zellij-sessionizer" "$zellij_sessionizer_test/home/sortable"

            cat > "$zellij_sessionizer_test/expected-zellij.log" <<'EOF'
            list-sessions --no-formatting
            attach sortable
            list-sessions --no-formatting
            attach -c sortable
            list-sessions --no-formatting
            attach sortable
            list-sessions --no-formatting
            attach --forget -c sortable
            EOF
            if ! cmp -s "$zellij_sessionizer_test/expected-zellij.log" "$zellij_sessionizer_test/zellij.log"; then
              echo "Expected zellij-sessionizer to query once and choose the command for each session state." >&2
              echo "Expected:" >&2
              ${pkgs.gnused}/bin/sed 's/^/  /' "$zellij_sessionizer_test/expected-zellij.log" >&2
              echo "Actual:" >&2
              ${pkgs.gnused}/bin/sed 's/^/  /' "$zellij_sessionizer_test/zellij.log" >&2
              exit 1
            fi

            zellij_scrub_test="$TMPDIR/zellij-legacy-args-scrub"
            zellij_scrub_cache="$zellij_scrub_test/cache"
            corrupt_layout="$zellij_scrub_cache/zellij/contract_version_1/session_info/corrupt/session-layout.kdl"
            unrelated_layout="$zellij_scrub_cache/zellij/0.44.1/session_info/unrelated/session-layout.kdl"
            mkdir -p "$(${pkgs.coreutils}/bin/dirname "$corrupt_layout")" "$(${pkgs.coreutils}/bin/dirname "$unrelated_layout")"

            cat > "$corrupt_layout" <<'EOF'
            layout {
                pane command="npm" {
                    args "exec" "@upstash/context7-mcp" "--api-key" "legacy-secret" "--transport" "stdio"
                }
            }
            EOF
            chmod 0644 "$corrupt_layout"

            cat > "$unrelated_layout" <<'EOF'
            layout {
                pane command="example" {
                    args "--api-key" "unrelated-value"
                }
            }
            EOF
            chmod 0644 "$unrelated_layout"
            cp "$unrelated_layout" "$zellij_scrub_test/unrelated.expected"

            run_expect 0 zellij-legacy-args-scrub env \
              HOME="$zellij_scrub_test/home" \
              XDG_CACHE_HOME="$zellij_scrub_cache" \
              ${pkgs.bash}/bin/bash "$desktop_zellij_legacy_args_scrub_activation"
            assert_log_not_contains "legacy-secret"

            if ${pkgs.gnugrep}/bin/grep -Fq -- '--api-key' "$corrupt_layout" \
              || ${pkgs.gnugrep}/bin/grep -Fq -- 'legacy-secret' "$corrupt_layout"; then
              echo "Expected Zellij activation to remove legacy Context7 API-key arguments." >&2
              exit 1
            fi
            if ! ${pkgs.gnugrep}/bin/grep -Fq -- '"--transport" "stdio"' "$corrupt_layout"; then
              echo "Expected Zellij activation to preserve non-secret Context7 arguments." >&2
              exit 1
            fi
            if [ "$(${pkgs.coreutils}/bin/stat -c '%a' "$corrupt_layout")" != 600 ]; then
              echo "Expected scrubbed Zellij layout permissions to be 0600." >&2
              exit 1
            fi
            if ! cmp -s "$zellij_scrub_test/unrelated.expected" "$unrelated_layout"; then
              echo "Expected Zellij activation to leave unrelated layouts untouched." >&2
              exit 1
            fi
            if [ "$(${pkgs.coreutils}/bin/stat -c '%a' "$unrelated_layout")" != 644 ]; then
              echo "Expected Zellij activation to preserve permissions on unrelated layouts." >&2
              exit 1
            fi

            cp "$corrupt_layout" "$zellij_scrub_test/corrupt.scrubbed"
            run_expect 0 zellij-legacy-args-scrub-idempotent env \
              HOME="$zellij_scrub_test/home" \
              XDG_CACHE_HOME="$zellij_scrub_cache" \
              ${pkgs.bash}/bin/bash "$desktop_zellij_legacy_args_scrub_activation"
            if ! cmp -s "$zellij_scrub_test/corrupt.scrubbed" "$corrupt_layout"; then
              echo "Expected repeated Zellij legacy argument scrubbing to be idempotent." >&2
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

            context7_wrapper_path="$(${pkgs.gnused}/bin/sed -n '
              /^\[mcp_servers.context7\]$/,/^\[/ {
                s|^command = "\(/nix/store/[^"]*/bin/context7-mcp\)"$|\1|p
              }
            ' "$codex_seed_path" | head -n1)"
            if [ -z "$context7_wrapper_path" ] || [ ! -f "$context7_wrapper_path" ]; then
              echo "Expected generated Codex config to reference the Context7 wrapper." >&2
              ${pkgs.gnused}/bin/sed -n '/^\[mcp_servers.context7\]$/,/^\[/p' "$codex_seed_path" >&2
              exit 1
            fi

            assert_file_contains \
              "$context7_wrapper_path" \
              'export CONTEXT7_API_KEY="$api_key"' \
              "Expected Context7 wrapper to pass the API key through the environment."
            assert_not_file_contains \
              "$context7_wrapper_path" \
              '--api-key' \
              "Context7 wrapper must not expose the API key in process arguments."

            assert_log_contains_file \
              "experimental_use_rmcp_client = true" \
              "$codex_seed_path" \
              "Expected Codex config to enable the remote MCP client required by Linear OAuth."

            assert_log_contains_file \
              'url = "https://mcp.linear.app/mcp"' \
              "$codex_seed_path" \
              "Expected Codex config to include the Linear MCP server."

            assert_log_contains_file \
              'model = "gpt-5.6-terra"' \
              "$codex_seed_path" \
              "Expected Codex config to use the GPT-5.6 Terra model."

            if ${pkgs.gnugrep}/bin/grep -Fq 'model = "gpt-5.6"' "$codex_seed_path"; then
              echo "Codex config must not use the unsupported bare GPT-5.6 model alias." >&2
              exit 1
            fi

            assert_log_contains_file \
              'model_reasoning_effort = "high"' \
              "$codex_seed_path" \
              "Expected Codex config to retain high reasoning for normal work."

            assert_log_contains_file \
              'plan_mode_reasoning_effort = "xhigh"' \
              "$codex_seed_path" \
              "Expected Codex config to retain xhigh reasoning for Plan Mode."

            codex_seed="$TMPDIR/codex-seed.toml"
            cat > "$codex_seed" <<'TOML'
            model = "gpt-5.6-terra"
            approval_policy = "on-request"

            [tui]
            vim_mode_default = true

            [projects."/home/stefan/system-manifest"]
            trust_level = "trusted"

            [features]
            goals = true

            [mcp_servers.context7]
            command = "/nix/store/context7-mcp/bin/context7-mcp"

            [[skills.config]]
            path = "/home/stefan/.agents/skills/grilling"
            enabled = true
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

            assert data["model"] == "gpt-5.6-terra"
            assert data["projects"]["/home/stefan/system-manifest"]["trust_level"] == "trusted"
            assert data["mcp_servers"]["context7"] == {
                "command": "/nix/store/context7-mcp/bin/context7-mcp",
            }
            assert data["skills"]["config"] == [{
                "path": "/home/stefan/.agents/skills/grilling",
                "enabled": True,
            }]
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

            [mcp_servers.context7]
            url = "https://mcp.context7.com/mcp/oauth"
            args = ["-y", "@upstash/context7-mcp", "--api-key", "stale"]

            [mcp_servers.local-test]
            command = "local-mcp"
            args = ["serve"]

            [[skills.config]]
            path = "/home/stefan/.agents/skills/ui-ux-pro-max"
            enabled = true
            TOML
            run_codex_merge "$existing"
            ${codexConfigPython}/bin/python3 - "$existing" <<'PY'
            from pathlib import Path
            import sys
            import tomllib

            with Path(sys.argv[1]).open("rb") as f:
                data = tomllib.load(f)

            assert data["model"] == "gpt-5.6-terra"
            assert data["local_only"] == "kept"
            assert data["features"]["goals"] is True
            assert data["features"]["local_flag"] is True
            assert data["projects"]["/home/stefan/system-manifest"]["trust_level"] == "trusted"
            assert data["projects"]["/tmp/other"]["trust_level"] == "trusted"
            assert data["mcp_servers"]["context7"] == {
                "command": "/nix/store/context7-mcp/bin/context7-mcp",
            }
            assert data["mcp_servers"]["local-test"] == {
                "command": "local-mcp",
                "args": ["serve"],
            }
            assert data["skills"]["config"] == [{
                "path": "/home/stefan/.agents/skills/grilling",
                "enabled": True,
            }]
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
            assert data["model"] == "gpt-5.6-terra"
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
            assert data["model"] == "gpt-5.6-terra"
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
            assert data["model"] == "gpt-5.6-terra"
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
