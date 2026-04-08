{
  pkgs,
  weConstants,
  weNormalizeDir,
  ...
}: {
  home.packages = [
    (pkgs.writeShellScriptBin ".wallpaper-hook" ''
            LOCKFILE="''${XDG_RUNTIME_DIR:-/tmp}/wallpaper-hook.lock"
            exec 9>"$LOCKFILE"
            if ! ${pkgs.util-linux}/bin/flock -n 9; then
              exit 1
            fi

            ${weConstants}
            ${weNormalizeDir}
            CACHE_WALL="$HOME/.cache/current_wallpaper"
            FALLBACK_CACHE="$HOME/.cache/quickshell-last-wallpaper"
            WE_WORKSHOP_ROOT="$WE_WORKSHOP"
            USB_LIGHT_MODE_FLAG="$HOME/.config/system-manifest/usb-light-mode-enabled"
            NORMAL_POLL_INTERVAL=2
            LIGHT_MODE_POLL_INTERVAL=8

            cleanup() {
              stop_all_we
              rm -f "$LOCKFILE"
            }
            trap cleanup EXIT SIGTERM

            # Wait for environment
            until hyprctl monitors &>/dev/null; do sleep 1; done
            sleep 1
            until dms ipc wallpaper get &>/dev/null; do sleep 0.5; done

            CURRENT_WALL=""
            LAST_COLORS_HASH=""
            LAST_VESKTOP_PALETTE_HASH=""
            LAST_POWER_PROFILE=""

            update_themes() {
              local color_file="$HOME/.config/hypr/dms/colors.conf"
              local palette_json="$HOME/.cache/DankMaterialShell/dms-colors.json"

              if [ -f "$color_file" ]; then
                local current_hash=""
                current_hash=$(${pkgs.coreutils}/bin/md5sum "$color_file" | cut -d' ' -f1)
                if [ "$current_hash" != "$LAST_COLORS_HASH" ]; then
                  LAST_COLORS_HASH="$current_hash"

                  PRIMARY=$(grep "\$primary =" "$color_file" | cut -d'(' -f2 | cut -d')' -f1 | sed 's/ff$//')
                  BG=$(grep "\$surface =" "$color_file" | cut -d'(' -f2 | cut -d')' -f1 | sed 's/ff$//')
                  FG=$(grep "\$onSurface =" "$color_file" | cut -d'(' -f2 | cut -d')' -f1 | sed 's/ff$//')
                  ACCENT=$(grep "\$secondary =" "$color_file" | cut -d'(' -f2 | cut -d')' -f1 | sed 's/ff$//')

                  # If primary is too dark, use accent instead
                  if [ -n "$PRIMARY" ] && [ $((''${#PRIMARY})) -ge 6 ] 2>/dev/null; then
                    PRIMARY_R=$((16#''${PRIMARY:0:2})) 2>/dev/null || PRIMARY_R=0
                    PRIMARY_G=$((16#''${PRIMARY:2:2})) 2>/dev/null || PRIMARY_G=0
                    PRIMARY_B=$((16#''${PRIMARY:4:2})) 2>/dev/null || PRIMARY_B=0
                    BRIGHTNESS=$(( (PRIMARY_R * 299 + PRIMARY_G * 587 + PRIMARY_B * 114) / 1000 ))
                    if [ "$BRIGHTNESS" -lt 80 ]; then
                      PRIMARY="$ACCENT"
                    fi
                  fi

                  echo "Updating Zathura colors..."
                  mkdir -p ~/.config/zathura
                  cat <<EOF > ~/.config/zathura/zathurarc
      set recolor "true"
      set completion-bg "#$BG"
      set completion-fg "#$FG"
      set completion-highlight-bg "#$PRIMARY"
      set completion-highlight-fg "#$BG"
      set recolor-lightcolor "#$BG"
      set recolor-darkcolor "#$FG"
      set default-bg "#$BG"
      set default-fg "#$FG"
      set statusbar-bg "#$BG"
      set statusbar-fg "#$FG"
      set inputbar-bg "#$BG"
      set inputbar-fg "#$FG"
      set notification-error-bg "#ff5555"
      set notification-error-fg "#$FG"
      set notification-warning-bg "#ffb86c"
      set notification-warning-fg "#$FG"
      set highlight-color "#$PRIMARY"
              set highlight-active-color "#$PRIMARY"
      EOF
                fi
              fi

              # Keep Transluence-derived Vesktop theme synchronized with the same
              # palette artifact it actually consumes, not just colors.conf.
              if command -v regen-vesktop-transluence-theme >/dev/null 2>&1 && [ -f "$palette_json" ]; then
                local current_palette_hash=""
                current_palette_hash=$(${pkgs.coreutils}/bin/md5sum "$palette_json" | cut -d' ' -f1)
                if [ "$current_palette_hash" != "$LAST_VESKTOP_PALETTE_HASH" ]; then
                  if regen-vesktop-transluence-theme; then
                    LAST_VESKTOP_PALETTE_HASH=$(${pkgs.coreutils}/bin/md5sum "$palette_json" | cut -d' ' -f1)
                  fi
                fi
              fi
            }

            resolve_direct_we_dir() {
              local candidate="$1"
              [ -d "$candidate" ] || return 1
              [ -f "$candidate/project.json" ] || return 1
              local normalized
              normalized=$(normalize_dir "$candidate" 2>/dev/null || true)
              [ -n "$normalized" ] || return 1
              case "$normalized" in
                "$WE_WORKSHOP_ROOT"/*|"$WE_DEFAULTS_ROOT"/*)
                  echo "$normalized"
                  return 0
                  ;;
              esac
              return 1
            }

            resolve_we_dir() {
              local wall_path="$1"

              local direct_dir=""
              direct_dir=$(resolve_direct_we_dir "$wall_path" || true)
              if [ -n "$direct_dir" ]; then
                echo "$direct_dir"
                return 0
              fi

              [ ! -f "$MAP_FILE" ] && return 1
              local bname
              bname=$(basename "$wall_path")
              local we_dir
              we_dir=$(${pkgs.jq}/bin/jq -r --arg k "$bname" '.[$k] // empty' "$MAP_FILE")
              if [ -n "$we_dir" ]; then
                local normalized
                normalized=$(normalize_dir "$we_dir" 2>/dev/null || true)
                if [ -n "$normalized" ]; then
                  echo "$normalized"
                  return 0
                fi
                echo "$we_dir"
                return 0
              fi
              return 1
            }

            resolve_we_dir_with_refresh() {
              local wall_path="$1"
              local resolved=""

              resolved=$(resolve_we_dir "$wall_path" || true)
              if [ -n "$resolved" ]; then
                echo "$resolved"
                return 0
              fi

              # Mapping can get stale/corrupted after interrupted sessions.
              # If current wallpaper comes from the synced folder, refresh once.
              if [ -f "$wall_path" ] && [ "''${wall_path#$HOME/wallpapers/.wallpaper-engine/}" != "$wall_path" ]; then
                wallpaper-engine-sync &>/dev/null || true
                resolved=$(resolve_we_dir "$wall_path" || true)
                if [ -n "$resolved" ]; then
                  echo "$resolved"
                  return 0
                fi
              fi

              return 1
            }

            current_we_dir() {
              local current_target=""
              current_target=$(systemctl --user show-environment 2>/dev/null \
                | grep '^WE_WALLPAPER_DIR=' | cut -d= -f2- || true)
              if [ -n "$current_target" ]; then
                current_target=$(normalize_dir "$current_target" 2>/dev/null || printf '%s\n' "$current_target")
              fi
              printf '%s\n' "$current_target"
            }

            publish_dms_wallpaper() {
              local image_path="$1"
              [ -n "$image_path" ] || return 1
              [ -f "$image_path" ] || return 1
              dms ipc wallpaper set "$image_path"
            }

            lookup_thumb_by_dir() {
              local dir="$1"
              [ -f "$MAP_FILE" ] || return 1
              ${pkgs.jq}/bin/jq -r --arg dir "$dir" '
                  to_entries[]
                  | select((.value | sub("/$"; "")) == $dir)
                  | .key
              ' "$MAP_FILE" | ${pkgs.coreutils}/bin/head -n 1
            }

            lookup_thumb_by_id() {
              local wid="$1"
              [ -f "$MAP_FILE" ] || return 1
              ${pkgs.jq}/bin/jq -r --arg wid "$wid" '
                  to_entries[]
                  | select((.value | sub("/$"; "") | split("/") | last) == $wid)
                  | .key
              ' "$MAP_FILE" | ${pkgs.coreutils}/bin/head -n 1
            }

            # Look up the generated thumbnail for a WE directory and publish it
            # as DMS wallpaper. This advances SessionData.wallpaperPath and
            # triggers full DMS theme generation.
            publish_we_thumbnail() {
              local we_dir="$1"
              local thumb_dir="$WALL_DIR"

              local thumb_name=""
              thumb_name=$(lookup_thumb_by_dir "$we_dir" || true)
              if [ -z "$thumb_name" ]; then
                local workshop_id=""
                workshop_id=$(basename "$we_dir")
                thumb_name=$(lookup_thumb_by_id "$workshop_id" || true)
              fi

              local thumb_path=""
              if [ -n "$thumb_name" ]; then
                thumb_path="$thumb_dir/$thumb_name"
              fi

              if [ -n "$thumb_path" ] && [ -f "$thumb_path" ]; then
                publish_dms_wallpaper "$thumb_path"
                return $?
              fi

              # No thumbnail — try the author's preview.jpg directly
              local preview="$we_dir/preview.jpg"
              if [ -f "$preview" ]; then
                publish_dms_wallpaper "$preview"
                return $?
              fi
              return 1
            }

            WE_SLOT_FILE="$HOME/.cache/we-active-slot"

            # Start WE on the idle slot; once it renders, stop the old slot.
            swap_we_service() {
              local new_dir="$1" assets_dir="$2"
              local current_slot
              current_slot=$(cat "$WE_SLOT_FILE" 2>/dev/null || echo "a")
              local next_slot="b"
              [ "$current_slot" = "b" ] && next_slot="a"

              systemctl --user set-environment \
                WE_WALLPAPER_DIR="$new_dir" \
                WE_ASSETS_DIR="$assets_dir"
              systemctl --user start "linux-wallpaperengine-''${next_slot}.service"
              sleep 2
              systemctl --user stop "linux-wallpaperengine-''${current_slot}.service" 2>/dev/null || true
              echo "$next_slot" > "$WE_SLOT_FILE"
            }

            stop_all_we() {
              systemctl --user stop linux-wallpaperengine-a.service 2>/dev/null || true
              systemctl --user stop linux-wallpaperengine-b.service 2>/dev/null || true
              rm -f "$WE_SLOT_FILE"
            }

            # Check if either WE slot is active
            we_is_active() {
              local a b
              a=$(systemctl --user is-active linux-wallpaperengine-a.service 2>/dev/null || true)
              b=$(systemctl --user is-active linux-wallpaperengine-b.service 2>/dev/null || true)
              [ "$a" = "active" ] || [ "$a" = "activating" ] || \
              [ "$b" = "active" ] || [ "$b" = "activating" ]
            }

            usb_light_mode_enabled() {
              [ -f "$USB_LIGHT_MODE_FLAG" ]
            }

            current_power_profile() {
              if ! usb_light_mode_enabled; then
                printf 'balanced\n'
                return 0
              fi

              local profile=""
              profile="$(${pkgs.power-profiles-daemon}/bin/powerprofilesctl get 2>/dev/null || true)"
              case "$profile" in
                power-saver|balanced|performance)
                  printf '%s\n' "$profile"
                  ;;
                *)
                  printf 'balanced\n'
                  ;;
              esac
            }

            current_poll_interval() {
              if usb_light_mode_enabled && [ "$LAST_POWER_PROFILE" = "power-saver" ]; then
                printf '%s\n' "$LIGHT_MODE_POLL_INTERVAL"
              else
                printf '%s\n' "$NORMAL_POLL_INTERVAL"
              fi
            }

            apply_we_policy() {
              local requested_dir="$1"
              local normalized_dir=""
              local current_target=""

              [ -n "$requested_dir" ] || return 1
              normalized_dir=$(normalize_dir "$requested_dir" 2>/dev/null || printf '%s\n' "$requested_dir")
              publish_we_thumbnail "$normalized_dir" || true

              if usb_light_mode_enabled && [ "$LAST_POWER_PROFILE" = "power-saver" ]; then
                echo "USB light mode active: keeping static preview for $normalized_dir"
                stop_all_we
                return 0
              fi

              current_target=$(current_we_dir)
              if [ "$current_target" = "$normalized_dir" ] && we_is_active; then
                echo "Wallpaper Engine already running: $normalized_dir (skipped restart)"
                return 0
              fi

              echo "Wallpaper Engine: $normalized_dir"
              swap_we_service "$normalized_dir" "$WE_ASSETS"
            }

            handle_power_profile_change() {
              local profile="$1"
              local previous="$LAST_POWER_PROFILE"
              local target_wall=""
              local target_we_dir=""

              usb_light_mode_enabled || return 0
              [ "$profile" = "$LAST_POWER_PROFILE" ] && return 0
              LAST_POWER_PROFILE="$profile"

              echo "USB light mode profile: ''${previous:-unset} -> $profile"

              target_wall="$CURRENT_WALL"
              if [ -z "$target_wall" ]; then
                target_wall=$(dms ipc wallpaper get 2>/dev/null || true)
              fi
              if [ -n "$target_wall" ]; then
                target_we_dir=$(resolve_we_dir_with_refresh "$target_wall" || true)
              fi

              if [ "$profile" = "power-saver" ]; then
                if [ -n "$target_we_dir" ]; then
                  publish_we_thumbnail "$target_we_dir" || true
                fi
                stop_all_we
                return 0
              fi

              if [ -n "$target_we_dir" ]; then
                apply_we_policy "$target_we_dir"
              fi
            }

            # Ensure WE wallpaper map is fresh before first poll
            wallpaper-engine-sync &>/dev/null || true

            # Initial theme update on startup
            update_themes
            LAST_POWER_PROFILE=$(current_power_profile)

            # If DMS restored a static wallpaper, stop WE immediately so Hyprland
            # does not keep probing a crashed renderer and showing ANR popups.
            # If the cached wallpaper is a WE directory, start WE and capture live.
            initial_wall=$(dms ipc wallpaper get 2>/dev/null || true)
            boot_cache=""
            if [ -s "$CACHE_WALL" ]; then
              boot_cache=$(cat "$CACHE_WALL")
            fi
            fallback_wall=""
            if [ -s "$FALLBACK_CACHE" ]; then
              fallback_wall=$(cat "$FALLBACK_CACHE")
            fi

            # Check if boot cache points to a WE directory (new persistence format)
            boot_we_dir=""
            if [ -n "$fallback_wall" ]; then
              boot_we_dir=$(resolve_direct_we_dir "$fallback_wall" || true)
            fi
            if [ -z "$boot_we_dir" ] && [ -n "$boot_cache" ] && [ -d "$boot_cache" ] && [ -f "$boot_cache/project.json" ]; then
              boot_we_dir=$(normalize_dir "$boot_cache" 2>/dev/null || true)
            fi

            if [ -n "$boot_we_dir" ]; then
              # Boot restore: start WE on first slot and set thumbnail as DMS wallpaper
              echo "Boot restore: WE directory $boot_we_dir"
              apply_we_policy "$boot_we_dir"
            elif [ -n "$initial_wall" ]; then
              initial_we_dir=$(resolve_we_dir_with_refresh "$initial_wall" || true)
              if [ -n "$initial_we_dir" ]; then
                apply_we_policy "$initial_we_dir"
              else
                stop_all_we
              fi
            fi

            while true; do
              handle_power_profile_change "$(current_power_profile)"
              NEW_WALL=$(dms ipc wallpaper get 2>/dev/null)

              if [ -n "$NEW_WALL" ] && [ "$NEW_WALL" != "$CURRENT_WALL" ]; then
                CURRENT_WALL="$NEW_WALL"
                echo "$CURRENT_WALL" > "$CACHE_WALL"

                WE_DIR=$(resolve_we_dir_with_refresh "$NEW_WALL" || true)

                if [ -n "$WE_DIR" ]; then
                  apply_we_policy "$WE_DIR"
                else
                  # Static wallpaper — DMS renders it natively, just stop WE
                  echo "Static wallpaper: $NEW_WALL"
                  stop_all_we
                fi

              fi

              # Static wallpapers can lag behind the wallpaper-path change, so keep
              # polling Matugen output independently and let the color hash gate
              # skip no-op work once the new palette lands.
              update_themes
              sleep "$(current_poll_interval)"
            done
    '')
  ];
}
