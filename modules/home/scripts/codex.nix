{pkgs, ...}: let
  usb = import ../../shared/usb-constants.nix;
in {
  home.packages = [
    (pkgs.writeShellScriptBin "specify" ''
      exec ${pkgs.uv}/bin/uvx --from git+https://github.com/github/spec-kit.git specify "$@"
    '')
    (pkgs.writeShellScriptBin "codex-state-sync" ''
      set -euo pipefail
      MODE="''${1:-to-usb}"
      case "$MODE" in
        to-usb | from-usb) ;;
        *)
          echo "Usage: codex-state-sync [to-usb|from-usb]"
          exit 1
          ;;
      esac
      TEST_MODE="''${CODEX_STATE_SYNC_TEST_MODE:-0}"
      TEST_ROOT="''${CODEX_STATE_SYNC_TEST_ROOT:-}"
      LUKS_DEVICE="${usb.rootPartByLabel}"
      PREFERRED_MAPPER="${usb.mapperName}"
      MAPPER="$PREFERRED_MAPPER"
      MAPPER_DEV="/dev/mapper/$MAPPER"
      MOUNT="/mnt/usb-sync"

      if [ "$TEST_MODE" -eq 1 ]; then
        if [ -z "$TEST_ROOT" ]; then
          echo "CODEX_STATE_SYNC_TEST_ROOT is required in test mode." >&2
          exit 1
        fi
        SYNC_USER="$(${pkgs.coreutils}/bin/id -un)"
        SYNC_GROUP="$(${pkgs.coreutils}/bin/id -gn)"
        USER_HOME="$TEST_ROOT/local-home"
        MOUNT="$TEST_ROOT/usb-root"
      else
        SYNC_USER="''${SUDO_USER:-''${USER:-$(${pkgs.coreutils}/bin/id -un)}}"
        SYNC_GROUP="$(${pkgs.coreutils}/bin/id -gn "$SYNC_USER")"
        USER_HOME="$(${pkgs.gawk}/bin/awk -F: -v user="$SYNC_USER" '$1 == user { print $6; exit }' /etc/passwd)"
      fi

      LOCAL="$USER_HOME/.codex"
      REMOTE="$MOUNT$USER_HOME/.codex"
      BACKUP_TIMESTAMP="$(${pkgs.coreutils}/bin/date -u +%Y%m%dT%H%M%SZ)"
      if [ "$TEST_MODE" -eq 1 ] && [ -n "''${CODEX_STATE_SYNC_TEST_TIMESTAMP:-}" ]; then
        BACKUP_TIMESTAMP="$CODEX_STATE_SYNC_TEST_TIMESTAMP"
      elif [ "$TEST_MODE" -ne 1 ]; then
        BACKUP_TIMESTAMP="$BACKUP_TIMESTAMP-$BASHPID"
      fi
      BACKUP_RUN_DIR="$USER_HOME/.local/state/codex-state-sync/backups/$BACKUP_TIMESTAMP/$MODE"
      BACKUP_DIR="$BACKUP_RUN_DIR/sessions"
      OPENED_MAPPER=0
      MOUNTED=0

      run_root() {
        if [ "$TEST_MODE" -eq 1 ] || [ "$EUID" -eq 0 ]; then
          "$@"
        else
          sudo "$@"
        fi
      }

      request_rollout_reindex() {
        local codex_root="$1"
        local candidate=""
        local state_db=""
        local state_version=""
        local latest_version=-1
        local state_backup_dir="$BACKUP_RUN_DIR/state"
        local state_backup=""
        local has_backfill_table=""

        for candidate in "$codex_root"/state_*.sqlite; do
          [ -f "$candidate" ] || continue
          state_version="''${candidate##*/state_}"
          state_version="''${state_version%.sqlite}"
          case "$state_version" in
            "" | *[!0-9]*) continue ;;
          esac
          if (( 10#$state_version > latest_version )); then
            latest_version=$((10#$state_version))
            state_db="$candidate"
          fi
        done

        if [ -z "$state_db" ]; then
          echo "No destination Codex database found; sessions will be indexed when one is created."
          return 0
        fi

        run_root mkdir -p "$state_backup_dir"
        run_root chown "$SYNC_USER:$SYNC_GROUP" "$state_backup_dir"
        state_backup="$state_backup_dir/''${state_db##*/}"
        run_root ${pkgs.sqlite}/bin/sqlite3 "$state_db" ".backup '$state_backup'"
        run_root chown "$SYNC_USER:$SYNC_GROUP" "$state_backup"

        has_backfill_table="$(
          run_root ${pkgs.sqlite}/bin/sqlite3 "$state_db" "
            SELECT COUNT(*)
            FROM sqlite_master
            WHERE type = 'table' AND name = 'backfill_state';
          "
        )"
        if [ "$has_backfill_table" -ne 1 ]; then
          echo "Destination Codex database has no rollout backfill state; backup saved at $state_backup."
          return 0
        fi

        run_root ${pkgs.sqlite}/bin/sqlite3 "$state_db" "
          BEGIN IMMEDIATE;
          INSERT INTO backfill_state (
            id,
            status,
            last_watermark,
            last_success_at,
            updated_at
          )
          VALUES (1, 'pending', NULL, NULL, unixepoch())
          ON CONFLICT(id) DO UPDATE SET
            status = 'pending',
            last_watermark = NULL,
            last_success_at = NULL,
            updated_at = unixepoch();
          COMMIT;
        "
        echo "Imported sessions will be indexed on the next Codex launch."
        echo "Pre-reindex database backup: $state_backup"
      }

      sync_sessions() {
        local source_sessions="$1"
        local destination_sessions="$2"
        local sync_items="$BACKUP_RUN_DIR/rsync-items.log"

        SESSIONS_CHANGED=0
        run_root ${pkgs.rsync}/bin/rsync -av --update --checksum --backup \
          --itemize-changes --out-format='%i %n%L' \
          --backup-dir="$BACKUP_DIR" --chown="$SYNC_USER:$SYNC_GROUP" \
          "$source_sessions/" "$destination_sessions/" >"$sync_items"
        ${pkgs.coreutils}/bin/cat "$sync_items"

        while IFS= read -r item; do
          if [[ "$item" == ">f"* ]]; then
            SESSIONS_CHANGED=1
            break
          fi
        done < "$sync_items"
      }

      refresh_mapper() {
        local existing_mapper=""
        existing_mapper=$(${pkgs.util-linux}/bin/lsblk -nrpo NAME,TYPE "$LUKS_DEVICE" 2>/dev/null | ${pkgs.gnused}/bin/sed -n '/ crypt$/ { s/ crypt$//; p; q; }')
        if [ -n "$existing_mapper" ]; then
          MAPPER_DEV="$existing_mapper"
          MAPPER="''${existing_mapper##*/}"
        else
          MAPPER="$PREFERRED_MAPPER"
          MAPPER_DEV="/dev/mapper/$MAPPER"
        fi
      }

      cleanup() {
        local rc=$?
        trap - EXIT INT TERM

        if [ "$MOUNTED" -eq 1 ] && run_root ${pkgs.util-linux}/bin/mountpoint -q "$MOUNT"; then
          run_root ${pkgs.util-linux}/bin/umount -R "$MOUNT" 2>/dev/null || true
          MOUNTED=0
        fi

        if [ "$OPENED_MAPPER" -eq 1 ]; then
          sync
          for _ in 1 2 3; do
            if run_root ${pkgs.cryptsetup}/bin/cryptsetup luksClose "$MAPPER" 2>/dev/null; then
              OPENED_MAPPER=0
              break
            fi
            sleep 1
          done

          if [ "$OPENED_MAPPER" -eq 1 ]; then
            echo "Warning: failed to close $MAPPER; close it manually with: sudo cryptsetup luksClose $MAPPER" >&2
            if [ "$rc" -eq 0 ]; then
              rc=1
            fi
          fi
        fi

        exit "$rc"
      }

      trap cleanup EXIT
      trap 'exit 130' INT
      trap 'exit 143' TERM

      if [ -z "$USER_HOME" ]; then
        echo "Unable to resolve a home directory for $SYNC_USER."
        exit 1
      fi

      codex_running=0
      if [ "$TEST_MODE" -eq 1 ]; then
        codex_running="''${CODEX_STATE_SYNC_TEST_CODEX_RUNNING:-0}"
      elif ${pkgs.procps}/bin/pgrep -u "$SYNC_USER" -x 'codex|upstream-codex' >/dev/null; then
        codex_running=1
      fi
      if [ "$MODE" = from-usb ] && [ "$codex_running" -eq 1 ]; then
        echo "Close Codex before importing USB sessions." >&2
        echo "A running destination process can rewrite imported session state." >&2
        exit 1
      fi

      if [ "$TEST_MODE" -ne 1 ]; then
        if [ ! -e "$LUKS_DEVICE" ]; then
          echo "USB not found. Plug in the USB drive and try again."
          exit 1
        fi

        refresh_mapper
        if [ ! -e "$MAPPER_DEV" ]; then
          run_root ${pkgs.cryptsetup}/bin/cryptsetup luksOpen "$LUKS_DEVICE" "$PREFERRED_MAPPER"
          OPENED_MAPPER=1
          refresh_mapper
        elif ! ${pkgs.util-linux}/bin/findmnt -rn -S "$MAPPER_DEV" >/dev/null 2>&1; then
          OPENED_MAPPER=1
        fi

        run_root mkdir -p "$MOUNT"
        if run_root ${pkgs.util-linux}/bin/mountpoint -q "$MOUNT"; then
          run_root ${pkgs.util-linux}/bin/umount -R "$MOUNT"
        fi
        run_root mount "$MAPPER_DEV" "$MOUNT"
        MOUNTED=1
      fi

      run_root mkdir -p "$LOCAL/sessions" "$REMOTE/sessions"
      run_root mkdir -p "$BACKUP_DIR"
      run_root chown "$SYNC_USER:$SYNC_GROUP" \
        "$LOCAL" "$LOCAL/sessions" "$REMOTE" "$REMOTE/sessions" \
        "$BACKUP_RUN_DIR" "$BACKUP_DIR"

      case "$MODE" in
        to-usb)
          echo "Syncing desktop -> USB..."
          sync_sessions "$LOCAL/sessions" "$REMOTE/sessions"
          if [ "$SESSIONS_CHANGED" -eq 1 ]; then
            request_rollout_reindex "$REMOTE"
          fi
          ;;
        from-usb)
          echo "Syncing USB -> desktop..."
          sync_sessions "$REMOTE/sessions" "$LOCAL/sessions"
          if [ "$SESSIONS_CHANGED" -eq 1 ]; then
            request_rollout_reindex "$LOCAL"
          fi
          ;;
      esac

      echo "Done."
    '')
  ];
}
