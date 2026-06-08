{
  self,
  pkgs,
}: let
  desktopHome = self.nixosConfigurations.desktop.config.home-manager.users.stefan.home.path;
  desktopActivation = self.nixosConfigurations.desktop.config.home-manager.users.stefan.home.activationPackage;
  desktopSkwdDmsSyncHook = self.nixosConfigurations.desktop.config.home-manager.users.stefan.xdg.configFile."skwd-wall/scripts/sync-dms-wallpaper.sh".source;
  desktopZellijDevLayoutFile = pkgs.writeText "desktop-zellij-dev-layout" self.nixosConfigurations.desktop.config.home-manager.users.stefan.xdg.configFile."zellij/layouts/dev.kdl".text;
  usbHome = self.nixosConfigurations.usb.config.home-manager.users.stefan.home.path;
  usbInitrd = self.nixosConfigurations.usb.config.system.build.initialRamdisk;
  usbRamStoreInitrd = self.nixosConfigurations.usb.config.specialisation.ram-store.configuration.system.build.initialRamdisk;
  usbRamStorePrepareScript = pkgs.writeText "usb-ram-store-prepare-script" self.nixosConfigurations.usb.config.specialisation.ram-store.configuration.boot.initrd.systemd.services.initrd-usb-ram-store-prepare.script;
  usbHostAutoStoreInitrd = self.nixosConfigurations.usb.config.specialisation.host-auto-store.configuration.system.build.initialRamdisk;
  usbHostAutoStorePrepareScript = pkgs.writeText "usb-host-auto-store-prepare-script" self.nixosConfigurations.usb.config.specialisation.host-auto-store.configuration.boot.initrd.systemd.services.initrd-usb-host-auto-store-prepare.script;
  usbDmsServiceEnvironmentFile = builtins.toFile "usb-dms-service-environment" (
    builtins.concatStringsSep "\n"
    self.nixosConfigurations.usb.config.home-manager.users.stefan.systemd.user.services.dms.Service.Environment
  );
  codexConfigPython = pkgs.python3.withPackages (ps: [ps.tomli-w]);
  desktopNeovimInitFile = self.nixosConfigurations.desktop.config.home-manager.users.stefan.xdg.configFile."nvim/init.lua".source;
  neovimLangmapFile = builtins.toFile "neovim-langmap" self.nixosConfigurations.desktop.config.home-manager.users.stefan.programs.nixvim.opts.langmap;
  desktopHyprlandBindsFile = builtins.toFile "desktop-hyprland-binds" (
    builtins.concatStringsSep "\n"
    self.nixosConfigurations.desktop.config.home-manager.users.stefan.wayland.windowManager.hyprland.settings.bind
  );
  shellcheckScripts = [
    "${desktopHome}/bin/codex-state-sync"
    "${desktopHome}/bin/gsr-record"
    "${desktopHome}/bin/hypr-nav"
    "${desktopHome}/bin/hypr-quit-active"
    "${desktopHome}/bin/screenshot-path-copy"
    "${desktopHome}/bin/skwd-we-capture-still"
    "${desktopHome}/bin/spotify_player"
    "${desktopHome}/bin/transmission-port-sync"
    "${desktopHome}/bin/update-usb"
    "${desktopHome}/bin/zellij-sessionizer"
    "${desktopSkwdDmsSyncHook}"
    "${usbHome}/bin/spotify_player"
    "${usbHome}/bin/setup-persistent-usb"
  ];
in {
  desktop = self.nixosConfigurations.desktop.config.system.build.toplevel;
  usb = self.nixosConfigurations.usb.config.system.build.toplevel;
  laptop = self.nixosConfigurations.laptop.config.system.build.toplevel;
  usb-initrd-ordering =
    pkgs.runCommand "usb-initrd-ordering-check" {
      nativeBuildInputs = [
        pkgs.cpio
        pkgs.findutils
        pkgs.gnugrep
        pkgs.systemd
        pkgs.zstd
      ];
    } ''
      set -euo pipefail

      unpack_initrd() {
        local image="$1"
        local target="$2"
        mkdir -p "$target"
        (cd "$target" && zstdcat "$image/initrd" | cpio -id --quiet)
      }

      generate_mount_units() {
        local initrd_dir="$1"
        local generated_dir="$2"
        local fstab

        fstab="$(find "$initrd_dir/nix/store" -maxdepth 1 -type f -name '*-initrd-fstab' -print -quit)"
        if [ -z "$fstab" ]; then
          echo "Expected initrd-fstab in $initrd_dir." >&2
          find "$initrd_dir/nix/store" -maxdepth 1 -type f -print >&2
          exit 1
        fi

        mkdir -p "$generated_dir" "$generated_dir.early" "$generated_dir.late"
        SYSTEMD_IN_INITRD=1 SYSTEMD_SYSROOT_FSTAB="$fstab" \
          ${pkgs.systemd}/lib/systemd/system-generators/systemd-fstab-generator "$generated_dir" "$generated_dir.early" "$generated_dir.late"
      }

      find_unit() {
        local dir="$1"
        local pattern="$2"
        local unit

        unit="$(find "$dir" "$dir.early" "$dir.late" -type f -name "$pattern" -print -quit)"
        if [ -z "$unit" ]; then
          echo "Expected generated unit matching $pattern." >&2
          find "$dir" "$dir.early" "$dir.late" -type f -print >&2
          exit 1
        fi

        printf '%s\n' "$unit"
      }

      find_static_unit() {
        local initrd_dir="$1"
        local unit_name="$2"
        local unit

        unit="$(find "$initrd_dir" -type f -name "$unit_name" -print -quit)"
        if [ -z "$unit" ]; then
          echo "Expected static initrd unit $unit_name." >&2
          find "$initrd_dir" -type f -name '*.service' -print >&2
          exit 1
        fi

        printf '%s\n' "$unit"
      }

      assert_contains() {
        local needle="$1"
        local file="$2"
        local label="$3"

        if ! grep -Fq "$needle" "$file"; then
          echo "Expected $label to contain: $needle" >&2
          sed 's/^/  /' "$file" >&2
          exit 1
        fi
      }

      assert_default_units() {
        local generated_dir="$1"
        local ro_unit rw_unit store_unit

        ro_unit="$(find_unit "$generated_dir" 'sysroot-nix-.ro*store.mount')"
        rw_unit="$(find_unit "$generated_dir" 'sysroot-nix-.rw*store.mount')"
        store_unit="$(find_unit "$generated_dir" 'sysroot-nix-store.mount')"

        assert_contains "What=/sysroot/nix-store.squashfs" "$ro_unit" "default /nix/.ro-store unit"
        assert_contains "Where=/sysroot/nix/.ro-store" "$ro_unit" "default /nix/.ro-store unit"
        assert_contains "Type=squashfs" "$ro_unit" "default /nix/.ro-store unit"
        assert_contains "loop" "$ro_unit" "default /nix/.ro-store unit"
        assert_contains "threads=multi" "$ro_unit" "default /nix/.ro-store unit"

        assert_contains "What=tmpfs" "$rw_unit" "default /nix/.rw-store unit"
        assert_contains "Type=tmpfs" "$rw_unit" "default /nix/.rw-store unit"
        assert_contains "size=2048M" "$rw_unit" "default /nix/.rw-store unit"

        assert_contains "Type=overlay" "$store_unit" "default /nix/store unit"
        assert_contains "lowerdir=/sysroot/nix/.ro-store" "$store_unit" "default /nix/store unit"
        assert_contains "upperdir=/sysroot/nix/.rw-store/store" "$store_unit" "default /nix/store unit"
        assert_contains "workdir=/sysroot/nix/.rw-store/work" "$store_unit" "default /nix/store unit"
      }

      assert_ram_units() {
        local initrd_dir="$1"
        local generated_dir="$2"
        local ro_unit rw_unit prep_unit

        ro_unit="$(find_unit "$generated_dir" 'sysroot-nix-.ro*store.mount')"
        rw_unit="$(find_unit "$generated_dir" 'sysroot-nix-.rw*store.mount')"
        prep_unit="$(find_static_unit "$initrd_dir" 'initrd-usb-ram-store-prepare.service')"

        assert_contains "What=/sysroot/nix/.ram-store-image/nix-store.squashfs" "$ro_unit" "ram-store /nix/.ro-store unit"
        assert_contains "What=/sysroot/nix/.ram-store-rw" "$rw_unit" "ram-store /nix/.rw-store unit"
        assert_contains "Type=none" "$rw_unit" "ram-store /nix/.rw-store unit"
        assert_contains "bind" "$rw_unit" "ram-store /nix/.rw-store unit"
        assert_contains "Before=sysroot-nix-.ro\\x2dstore.mount sysroot-nix-.rw\\x2dstore.mount" "$prep_unit" "ram-store prep unit"
        assert_contains "${pkgs.util-linux}/bin/mountpoint -q" ${usbRamStorePrepareScript} "ram-store prep script"
        assert_contains "${pkgs.util-linux}/bin/mount -t tmpfs" ${usbRamStorePrepareScript} "ram-store prep script"
        assert_contains "${pkgs.coreutils}/bin/cp" ${usbRamStorePrepareScript} "ram-store prep script"
        assert_contains "writable-scratch-overlay-ram-lower" ${usbRamStorePrepareScript} "ram-store prep script"
        assert_contains "writable-scratch-overlay-usb-lower" ${usbRamStorePrepareScript} "ram-store prep script"
      }

      assert_host_auto_units() {
        local initrd_dir="$1"
        local generated_dir="$2"
        local ro_unit rw_unit prep_unit

        ro_unit="$(find_unit "$generated_dir" 'sysroot-nix-.ro*store.mount')"
        rw_unit="$(find_unit "$generated_dir" 'sysroot-nix-.rw*store.mount')"
        prep_unit="$(find_static_unit "$initrd_dir" 'initrd-usb-host-auto-store-prepare.service')"

        assert_contains "What=/sysroot/nix/.host-store/.nixos-usb/store/nix-store.squashfs" "$ro_unit" "host-auto /nix/.ro-store unit"
        assert_contains "What=/sysroot/nix/.host-store/.nixos-usb/store/rw" "$rw_unit" "host-auto /nix/.rw-store unit"
        assert_contains "Type=none" "$rw_unit" "host-auto /nix/.rw-store unit"
        assert_contains "bind" "$rw_unit" "host-auto /nix/.rw-store unit"
        assert_contains "find_host_store_candidates" ${usbHostAutoStorePrepareScript} "host-auto prep script"
        assert_contains "${pkgs.util-linux}/bin/lsblk" ${usbHostAutoStorePrepareScript} "host-auto prep script"
        assert_contains "${pkgs.util-linux}/bin/mountpoint -q" ${usbHostAutoStorePrepareScript} "host-auto prep script"
        assert_contains "${pkgs.util-linux}/bin/mount -o rw,noatime" ${usbHostAutoStorePrepareScript} "host-auto prep script"
        assert_contains ".nixos-usb/store" ${usbHostAutoStorePrepareScript} "host-auto prep script"
        assert_contains "writable-host-auto-overlay" ${usbHostAutoStorePrepareScript} "host-auto prep script"
        assert_contains "writable-overlay-host-auto-usb-fallback" ${usbHostAutoStorePrepareScript} "host-auto prep script"
      }

      unpack_initrd ${usbInitrd} default-initrd
      generate_mount_units default-initrd default-generated
      assert_default_units default-generated

      find_closure_unit="$(find_static_unit default-initrd 'initrd-find-nixos-closure.service')"
      assert_contains "RequiresMountsFor=/sysroot/nix/store" "$find_closure_unit" "initrd-find-nixos-closure unit"

      unpack_initrd ${usbRamStoreInitrd} ram-initrd
      generate_mount_units ram-initrd ram-generated
      assert_ram_units ram-initrd ram-generated

      unpack_initrd ${usbHostAutoStoreInitrd} host-auto-initrd
      generate_mount_units host-auto-initrd host-auto-generated
      assert_host_auto_units host-auto-initrd host-auto-generated

      touch "$out"
    '';
  hyprland-keybinds =
    pkgs.runCommand "hyprland-keybind-checks" {
      nativeBuildInputs = [
        pkgs.findutils
        pkgs.gnugrep
        pkgs.gnused
      ];
    } ''
      set -euo pipefail

      assert_bind() {
        local bind="$1"
        if ! grep -Fxq "$bind" ${desktopHyprlandBindsFile}; then
          echo "Expected desktop Hyprland bind: $bind" >&2
          sed 's/^/  /' ${desktopHyprlandBindsFile} >&2
          exit 1
        fi
      }

      assert_bind '$mod, grave, togglespecialworkspace, music'
      assert_bind '$mod SHIFT, grave, movetoworkspace, special:music'
      assert_bind '$mod CTRL, grave, movetoworkspacesilent, special:music'

      touch "$out"
    '';
  neovim-langmap =
    pkgs.runCommand "neovim-langmap-checks" {
      nativeBuildInputs = [pkgs.python3];
    } ''
      set -euo pipefail

      python3 - ${neovimLangmapFile} <<'PY'
      import sys
      from pathlib import Path

      text = Path(sys.argv[1]).read_text(encoding="utf-8")
      uppercase_greek = sorted({ch for ch in text if "\u0391" <= ch <= "\u03a9"})
      if uppercase_greek:
          print(
              "Neovim langmap must not contain uppercase Greek sources: "
              + ", ".join(uppercase_greek),
              file=sys.stderr,
          )
          raise SystemExit(1)

      chunks = []
      chunk = []
      escaped = False
      for ch in text.strip():
          if escaped:
              chunk.append(ch)
              escaped = False
          elif ch == "\\":
              escaped = True
          elif ch == ",":
              chunks.append("".join(chunk))
              chunk = []
          else:
              chunk.append(ch)
      if chunk:
          chunks.append("".join(chunk))

      punctuation_sources = sorted(
          {entry[0] for entry in chunks if entry and entry[0] in {":", ";"}}
      )
      if punctuation_sources:
          print(
              "Neovim langmap must not remap Vim punctuation command sources: "
              + ", ".join(punctuation_sources),
              file=sys.stderr,
          )
          raise SystemExit(1)
      PY

      cat > check-command-key.lua <<'LUA'
      local file = assert(io.open(os.getenv("LANGMAP_FILE"), "r"))
      local langmap = file:read("*a"):gsub("%s+$", "")
      file:close()

      vim.opt.langmap = langmap
      vim.v.errmsg = ""

      local keys = vim.api.nvim_replace_termcodes(":<Esc>", true, false, true)
      vim.api.nvim_feedkeys(keys, "xt", false)

      if vim.v.errmsg ~= "" then
        io.stderr:write("Neovim ':' command key failed under langmap: " .. vim.v.errmsg .. "\n")
        vim.cmd("cquit")
      end

      vim.cmd("qa!")
      LUA

      export HOME="$TMPDIR/home"
      export XDG_CACHE_HOME="$TMPDIR/cache"
      export XDG_CONFIG_HOME="$TMPDIR/config"
      export XDG_STATE_HOME="$TMPDIR/state"
      mkdir -p "$HOME" "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME" "$XDG_STATE_HOME"

      LANGMAP_FILE=${neovimLangmapFile} ${pkgs.coreutils}/bin/timeout 10s \
        ${desktopHome}/bin/nvim --headless -n -u NONE -i NONE \
        +"lua dofile('$PWD/check-command-key.lua')"

      touch "$out"
    '';
  neovim-lsp-health = pkgs.runCommand "neovim-lsp-health-check" {} ''
    set -euo pipefail

    export HOME="$TMPDIR/home"
    export XDG_CACHE_HOME="$TMPDIR/cache"
    export XDG_CONFIG_HOME="$TMPDIR/config"
    export XDG_STATE_HOME="$TMPDIR/state"
    mkdir -p "$HOME" "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME" "$XDG_STATE_HOME"

    cat > check-lsp-health.lua <<'LUA'
    vim.cmd("checkhealth vim.lsp")
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    local text = table.concat(lines, "\n")
    local unknown = {}

    for filetype in text:gmatch("Unknown filetype '([^']+)'") do
      table.insert(unknown, filetype)
    end

    if #unknown > 0 then
      io.stderr:write("Neovim LSP health reported unknown filetypes: " .. table.concat(unknown, ", ") .. "\n")
      vim.cmd("cquit")
    end

    vim.cmd("qa!")
    LUA

    ${pkgs.coreutils}/bin/timeout 20s \
      ${desktopHome}/bin/nvim --headless -n -i NONE -u ${desktopNeovimInitFile} \
      +"lua dofile('$PWD/check-lsp-health.lua')"

    touch "$out"
  '';
  wallpaper-runtime =
    pkgs.runCommand "wallpaper-runtime-checks" {
      nativeBuildInputs = [
        pkgs.coreutils
        pkgs.gnugrep
        pkgs.gnused
      ];
    } ''
      set -euo pipefail

      assert_executable() {
        local path="$1"
        local label="$2"

        if [ ! -x "$path" ]; then
          echo "Expected executable $label at $path" >&2
          exit 1
        fi
      }

      assert_contains() {
        local needle="$1"
        local file="$2"
        local label="$3"

        if ! grep -Fq "$needle" "$file"; then
          echo "Expected $label to contain: $needle" >&2
          sed 's/^/  /' "$file" >&2
          exit 1
        fi
      }

      assert_executable "${desktopHome}/bin/skwd" "skwd"
      assert_executable "${desktopHome}/bin/skwd-daemon" "skwd-daemon"
      assert_executable "${desktopHome}/bin/skwd-wall" "skwd-wall"
      assert_executable "${desktopHome}/bin/skwd-we-capture-still" "skwd-we-capture-still"
      assert_executable "${desktopSkwdDmsSyncHook}" "DMS wallpaper sync hook"

      skwd_bin="$(readlink -f "${desktopHome}/bin/skwd")"
      skwd_pkg="$(dirname "$(dirname "$skwd_bin")")"
      assert_executable "$skwd_pkg/libexec/skwd-wall/awww" "skwd-wall awww helper"
      assert_executable "$skwd_pkg/libexec/skwd-wall/linux-wallpaperengine" "skwd-wall Wallpaper Engine helper"

      assert_contains "sync-dms-wallpaper: missing both" "${desktopSkwdDmsSyncHook}" "DMS wallpaper sync hook"
      assert_contains "skwd-we-capture-still" "${desktopHome}/bin/skwd-we-capture-still" "Wallpaper Engine capture helper"
      assert_contains "# selector navigation" ${../modules/home/wallpaper/qml-patches.nix} "skwd-wall QML patch module"
      assert_contains "# filter bar keyboard" ${../modules/home/wallpaper/qml-patches.nix} "skwd-wall QML patch module"
      assert_contains "# tag cloud keyboard" ${../modules/home/wallpaper/qml-patches.nix} "skwd-wall QML patch module"
      assert_contains "# settings keyboard" ${../modules/home/wallpaper/qml-patches.nix} "skwd-wall QML patch module"
      assert_contains "# apply-service backends" ${../modules/home/wallpaper/qml-patches.nix} "skwd-wall QML patch module"

      if grep -Fq "'} else if (event.key === Qt.Key_Right) {'," ${../modules/home/wallpaper/qml-patches.nix}; then
        echo "skwd-wall QML patch module still contains the confirmed no-op Qt.Key_Right replacement." >&2
        exit 1
      fi

      touch "$out"
    '';
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

      if ! ${pkgs.gnugrep}/bin/grep -Fq "#/nix/store/}/init" "$desktop_home/bin/update-usb"; then
        echo "Expected update-usb to normalize squashfs verification paths relative to /nix/store." >&2
        ${pkgs.gnused}/bin/sed -n '180,230p' "$desktop_home/bin/update-usb" >&2
        exit 1
      fi

      if ! ${pkgs.gnugrep}/bin/grep -Fq "cryptsetup close --deferred" "$desktop_home/bin/update-usb"; then
        echo "Expected update-usb cleanup to defer LUKS close until nested mounts release." >&2
        ${pkgs.gnused}/bin/sed -n '120,180p' "$desktop_home/bin/update-usb" >&2
        exit 1
      fi

      if ! ${pkgs.gnugrep}/bin/grep -Fq "findmnt -Rrn" "$desktop_home/bin/update-usb"; then
        echo "Expected update-usb cleanup to unmount nested filesystems deepest-first." >&2
        ${pkgs.gnused}/bin/sed -n '110,170p' "$desktop_home/bin/update-usb" >&2
        exit 1
      fi

      if ! ${pkgs.gnugrep}/bin/grep -Fq "#nixosConfigurations.usb.config.system.build.toplevel" "$desktop_home/bin/update-usb"; then
        echo "Expected update-usb to prebuild the USB system toplevel attribute directly." >&2
        ${pkgs.gnused}/bin/sed -n '300,360p' "$desktop_home/bin/update-usb" >&2
        exit 1
      fi

      if ! ${pkgs.gnugrep}/bin/grep -Fq "Existing USB squashfs already contains the desired system; skipping update." "$desktop_home/bin/update-usb"; then
        echo "Expected update-usb to skip duplicate squashfs copies when the desired system is already present." >&2
        ${pkgs.gnused}/bin/sed -n '300,390p' "$desktop_home/bin/update-usb" >&2
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
  shellcheck =
    pkgs.runCommand "shellcheck-scripts" {
      nativeBuildInputs = [pkgs.shellcheck];
    } ''
      set -euo pipefail
      shellcheck -S warning ${pkgs.lib.escapeShellArgs shellcheckScripts}
      touch "$out"
    '';
}
