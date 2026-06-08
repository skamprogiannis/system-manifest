{
  pkgs,
  skwdWallBase,
  skwdApplyStaticWallpaper,
  skwdApplyWeStill,
  steamWorkshopDir,
  steamWeAssetsDir,
  skwdSecretsFile,
}: let
  qmlPatches = import ./qml-patches.nix {
    inherit pkgs skwdApplyStaticWallpaper skwdApplyWeStill;
  };
  inherit (qmlPatches) patchPython;
  qmlPatchScript = pkgs.writeText "skwd-wall-qml-patches.py" patchPython;
in {
  skwdWallPkg = pkgs.runCommand "skwd-wall-patched" {} ''
        cp -rL ${skwdWallBase} $out
        chmod -R u+w $out

        qml=$out/share/skwd-wall/qml/wallpaper/WallpaperSelector.qml
        settingsQml=$out/share/skwd-wall/qml/wallpaper/SettingsPanel.qml
        filterBarQml=$out/share/skwd-wall/qml/wallpaper/FilterBar.qml
        filterButtonQml=$out/share/skwd-wall/qml/wallpaper/FilterButton.qml
        settingsToggleQml=$out/share/skwd-wall/qml/wallpaper/SettingsToggle.qml
        settingsInputQml=$out/share/skwd-wall/qml/wallpaper/SettingsInput.qml
        settingsComboQml=$out/share/skwd-wall/qml/wallpaper/SettingsCombo.qml
        applyQml=$out/share/skwd-wall/qml/services/WallpaperApplyService.qml
        selectorServiceQml=$out/share/skwd-wall/qml/wallpaper/WallpaperSelectorService.qml
        sliceDelegateQml=$out/share/skwd-wall/qml/wallpaper/SliceDelegate.qml
        hexDelegateQml=$out/share/skwd-wall/qml/wallpaper/HexDelegate.qml
        tagCloudQml=$out/share/skwd-wall/qml/wallpaper/TagCloud.qml
        desktopFile=$out/share/applications/skwd-wall.desktop

        # --- vim-style hjkl aliases for arrow keys ---
        substituteInPlace $qml \
          --replace-fail \
            'event.key === Qt.Key_Left && !(event.modifiers & Qt.ShiftModifier)' \
            '(event.key === Qt.Key_Left || event.key === Qt.Key_H || event.text === "h") && !(event.modifiers & Qt.ShiftModifier)' \
          --replace-fail \
            'event.key === Qt.Key_Right && !(event.modifiers & Qt.ShiftModifier)' \
            '(event.key === Qt.Key_Right || event.key === Qt.Key_L || event.text === "l") && !(event.modifiers & Qt.ShiftModifier)' \
          --replace-fail \
            'event.key === Qt.Key_Up && !(event.modifiers & Qt.ShiftModifier)' \
            '(event.key === Qt.Key_Up || event.key === Qt.Key_K || event.text === "k") && !(event.modifiers & Qt.ShiftModifier)' \
          --replace-fail \
            'event.key === Qt.Key_Down && !(event.modifiers & Qt.ShiftModifier)' \
            '(event.key === Qt.Key_Down || event.key === Qt.Key_J || event.text === "j") && !(event.modifiers & Qt.ShiftModifier)'

        substituteInPlace $desktopFile \
          --replace-fail 'Name=Skwd-wall' 'Name=skwd-wall'
        if grep -q '^GenericName=Skwd-wall$' "$desktopFile"; then
          substituteInPlace $desktopFile \
            --replace-fail 'GenericName=Skwd-wall' 'GenericName=skwd-wall'
        fi
        desktopTmp="$desktopFile.tmp"
        : > "$desktopTmp"
        while IFS= read -r line || [ -n "$line" ]; do
          case "$line" in
            Icon=*)
              continue
              ;;
            *Icon=*)
              line="''${line%%Icon=*}"
              ;;
          esac
          printf '%s\n' "$line" >> "$desktopTmp"
        done < "$desktopFile"
        printf 'Icon=preferences-desktop-wallpaper\n' >> "$desktopTmp"
        mv "$desktopTmp" "$desktopFile"

        mkdir -p $out/libexec/skwd-wall
        cat > $out/libexec/skwd-wall/linux-wallpaperengine <<'EOF'
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    real_engine="${pkgs.linux-wallpaperengine}/bin/linux-wallpaperengine"
    workshop_dir="${steamWorkshopDir}"
    assets_dir="${steamWeAssetsDir}"
    state_dir="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/skwd"
    pid_file="$state_dir/linux-wallpaperengine-render.pids"

    args=()
    rewrote_background=0
    has_assets_dir=0
    expect_bg_value=0
    rewrite_background_output=""

    rewrite_background() {
      local value="$1"
      rewrite_background_output="$value"
      if [[ "$value" =~ ^[0-9]+$ ]] && [ -d "$workshop_dir/$value" ]; then
        rewrote_background=1
        rewrite_background_output="$workshop_dir/$value"
      fi
    }

    for arg in "$@"; do
      if [ "$expect_bg_value" -eq 1 ]; then
        rewrite_background "$arg"
        args+=("$rewrite_background_output")
        expect_bg_value=0
        continue
      fi

      case "$arg" in
        --assets-dir)
          has_assets_dir=1
          args+=("$arg")
          ;;
        --bg|-b)
          expect_bg_value=1
          args+=("$arg")
          ;;
        *)
          args+=("$arg")
          ;;
      esac
    done

    kill_recorded_renderers() {
      [ -f "$pid_file" ] || return 0

      while IFS= read -r pid; do
        [[ "$pid" =~ ^[0-9]+$ ]] || continue
        kill "$pid" 2>/dev/null || true
      done < "$pid_file"

      for _ in $(seq 1 20); do
        active=0
        while IFS= read -r pid; do
          [[ "$pid" =~ ^[0-9]+$ ]] || continue
          if kill -0 "$pid" 2>/dev/null; then
            active=1
            break
          fi
        done < "$pid_file"
        [ "$active" -eq 0 ] && break
        sleep 0.1
      done

      while IFS= read -r pid; do
        [[ "$pid" =~ ^[0-9]+$ ]] || continue
        if kill -0 "$pid" 2>/dev/null; then
          kill -9 "$pid" 2>/dev/null || true
        fi
      done < "$pid_file"

      rm -f "$pid_file"
    }

    if [ "''${#args[@]}" -gt 0 ]; then
      last_index=$((''${#args[@]} - 1))
      rewrite_background "''${args[$last_index]}"
      args[$last_index]="$rewrite_background_output"
    fi

    if [ "$rewrote_background" -eq 1 ] && [ "$has_assets_dir" -eq 0 ] && [ -d "$assets_dir" ]; then
      args=(--assets-dir "$assets_dir" "''${args[@]}")
    fi

    screen_roots=()
    screen_scalings=()
    common_args=()
    current_root_index=-1
    arg_count="''${#args[@]}"
    i=0
    while [ "$i" -lt "$arg_count" ]; do
      arg="''${args[$i]}"
      case "$arg" in
        --screen-root)
          i=$((i + 1))
          if [ "$i" -ge "$arg_count" ]; then
            echo "linux-wallpaperengine wrapper: missing value for --screen-root" >&2
            exit 1
          fi
          screen_roots+=("''${args[$i]}")
          screen_scalings+=("")
          current_root_index=$((''${#screen_roots[@]} - 1))
          ;;
        --scaling)
          i=$((i + 1))
          if [ "$i" -ge "$arg_count" ]; then
            echo "linux-wallpaperengine wrapper: missing value for --scaling" >&2
            exit 1
          fi
          if [ "$current_root_index" -ge 0 ]; then
            screen_scalings[$current_root_index]="''${args[$i]}"
          else
            common_args+=("$arg" "''${args[$i]}")
          fi
          ;;
        *)
          common_args+=("$arg")
          ;;
      esac
      i=$((i + 1))
    done

    if [ "''${#screen_roots[@]}" -eq 0 ]; then
      exec "$real_engine" "''${args[@]}"
    fi

    mkdir -p "$state_dir"
    kill_recorded_renderers

    pids=()
    pid_snapshot=""
    cleanup_children() {
      for pid in "''${pids[@]:-}"; do
        if [ -n "$pid" ]; then
          kill "$pid" 2>/dev/null || true
        fi
      done
    }

    cleanup_pid_file() {
      [ -n "$pid_snapshot" ] || return 0
      if [ -f "$pid_file" ] && [ "$(${pkgs.coreutils}/bin/cat "$pid_file" 2>/dev/null)" = "$pid_snapshot" ]; then
        rm -f "$pid_file"
      fi
    }

    trap 'cleanup_children' INT TERM
    trap 'cleanup_pid_file' EXIT

    if [ "''${#screen_roots[@]}" -eq 1 ]; then
      "$real_engine" "''${args[@]}" &
      pids=("$!")
      pid_snapshot=$(IFS=:; printf '%s' "''${pids[*]}")
      printf '%s' "$pid_snapshot" > "$pid_file"
      status=0
      for pid in "''${pids[@]}"; do
        if ! wait "$pid"; then
          status=1
        fi
      done
      exit "$status"
    fi

    background_arg=""
    common_prefix=("''${common_args[@]}")
    if [ "''${#common_args[@]}" -gt 0 ]; then
      last_index=$((''${#common_args[@]} - 1))
      background_arg="''${common_args[$last_index]}"
      common_prefix=("''${common_args[@]:0:$last_index}")
    fi

    status=0
    for idx in "''${!screen_roots[@]}"; do
      child_args=("''${common_prefix[@]}" --screen-root "''${screen_roots[$idx]}")
      if [ -n "''${screen_scalings[$idx]}" ]; then
        child_args+=(--scaling "''${screen_scalings[$idx]}")
      fi
      if [ -n "$background_arg" ]; then
        child_args+=("$background_arg")
      fi
      "$real_engine" "''${child_args[@]}" &
      pids+=("$!")
    done

    pid_snapshot=$(IFS=:; printf '%s' "''${pids[*]}")
    printf '%s' "$pid_snapshot" > "$pid_file"

    for pid in "''${pids[@]}"; do
      if ! wait "$pid"; then
        status=1
      fi
    done

    exit "$status"
    EOF
        chmod +x $out/libexec/skwd-wall/linux-wallpaperengine

        cat > $out/libexec/skwd-wall/awww <<'EOF'
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    real_awww="${pkgs.awww}/bin/awww"
    apply_static="${skwdApplyStaticWallpaper}"

    if [ "''${1:-}" != "img" ]; then
      exec "$real_awww" "$@"
    fi
    shift

    orig=("''${@}")
    outputs_csv=""
    image=""

    while [ "$#" -gt 0 ]; do
      case "$1" in
        -o|--outputs)
          if [ "$#" -lt 2 ]; then
            exec "$real_awww" img "''${orig[@]}"
          fi
          outputs_csv="$2"
          shift 2
          ;;
        --outputs=*)
          outputs_csv="''${1#*=}"
          shift
          ;;
        --transition-type|--transition-step|--transition-duration|--transition-fps|--transition-angle|--transition-pos|--transition-bezier|--transition-wave)
          if [ "$#" -lt 2 ]; then
            exec "$real_awww" img "''${orig[@]}"
          fi
          shift 2
          ;;
        --invert-y|-a|--all|--no-resize)
          exec "$real_awww" img "''${orig[@]}"
          ;;
        -*)
          exec "$real_awww" img "''${orig[@]}"
          ;;
        *)
          if [ -n "$image" ]; then
            exec "$real_awww" img "''${orig[@]}"
          fi
          image="$1"
          shift
          ;;
      esac
    done

    if [ -z "$image" ]; then
      exec "$real_awww" img "''${orig[@]}"
    fi

    if [ -n "$outputs_csv" ]; then
      exec "$apply_static" "$image" "$outputs_csv"
    fi
    exec "$apply_static" "$image"
    EOF
        chmod +x $out/libexec/skwd-wall/awww

        export OUT_PATH="$out"
        export BASE_PATH="${skwdWallBase}"
        export HELPER_DIR="$out/libexec/skwd-wall"
        export QML_PATH="$qml"
        export SETTINGS_QML="$settingsQml"
        export FILTER_BAR_QML="$filterBarQml"
        export FILTER_BUTTON_QML="$filterButtonQml"
        export SETTINGS_TOGGLE_QML="$settingsToggleQml"
        export SETTINGS_INPUT_QML="$settingsInputQml"
        export SETTINGS_COMBO_QML="$settingsComboQml"
        export APPLY_QML="$applyQml"
        export SELECTOR_SERVICE_QML="$selectorServiceQml"
        export SLICE_DELEGATE_QML="$sliceDelegateQml"
        export HEX_DELEGATE_QML="$hexDelegateQml"
        export TAG_CLOUD_QML="$tagCloudQml"
        export SECRETS_FILE_PATH="${skwdSecretsFile}"
        ${pkgs.python3}/bin/python3 ${qmlPatchScript}
  '';
}
