{
  description = "Stefan's NixOS";

  inputs = {
    # We use unstable to get the latest Hyprland and Ghostty
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixvim = {
      url = "github:nix-community/nixvim";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    skwd-wall.url = "github:liixini/skwd-wall";

    pearpass-app-desktop = {
      url = "github:tetherto/pearpass-app-desktop";
      flake = false;
    };

    visual-explainer = {
      url = "github:nicobailon/visual-explainer";
      flake = false;
    };

    impeccable = {
      url = "github:pbakaus/impeccable";
      flake = false;
    };

    ui-ux-pro-max = {
      url = "github:nextlevelbuilder/ui-ux-pro-max-skill";
      flake = false;
    };

    caveman = {
      url = "github:JuliusBrussee/caveman";
      flake = false;
    };

    mattpocock-skills = {
      url = "github:mattpocock/skills";
      flake = false;
    };

    trailofbits-skills = {
      url = "github:trailofbits/skills";
      flake = false;
    };

    dms = {
      url = "github:AvengeMedia/DankMaterialShell";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    hyprland = {
      url = "github:hyprwm/Hyprland";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    ghostty = {
      url = "github:ghostty-org/ghostty";
      # Intentionally NOT following nixpkgs so ghostty uses its own pinned rev,
      # matching what ghostty.cachix.org was built against for cache hits.
    };
  };

  outputs = {
    self,
    nixpkgs,
    home-manager,
    ...
  } @ inputs: let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};
  in {
    formatter.${system} = pkgs.alejandra;

    checks.${system} = let
      desktopHome = self.nixosConfigurations.desktop.config.home-manager.users.stefan.home.path;
      usbHome = self.nixosConfigurations.usb.config.home-manager.users.stefan.home.path;
      usbInitrd = self.nixosConfigurations.usb.config.system.build.initialRamdisk;
      usbRamStoreInitrd = self.nixosConfigurations.usb.config.specialisation.ram-store.configuration.system.build.initialRamdisk;
      usbRamStorePrepareScript = builtins.toFile "usb-ram-store-prepare-script" self.nixosConfigurations.usb.config.specialisation.ram-store.configuration.boot.initrd.systemd.services.initrd-usb-ram-store-prepare.script;
      usbHostAutoStoreInitrd = self.nixosConfigurations.usb.config.specialisation.host-auto-store.configuration.system.build.initialRamdisk;
      usbHostAutoStorePrepareScript = builtins.toFile "usb-host-auto-store-prepare-script" self.nixosConfigurations.usb.config.specialisation.host-auto-store.configuration.boot.initrd.systemd.services.initrd-usb-host-auto-store-prepare.script;
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
        "${desktopHome}/bin/spotify_player"
        "${desktopHome}/bin/transmission-port-sync"
        "${desktopHome}/bin/update-usb"
        "${desktopHome}/bin/zellij-sessionizer"
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
      script-smoke =
        pkgs.runCommand "script-smoke-checks" {
          nativeBuildInputs = [
            pkgs.gnugrep
            pkgs.gnused
          ];
        } ''
          set -euo pipefail

          desktop_home="${desktopHome}"
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

          if ! ${pkgs.gnugrep}/bin/grep -Fq "#/nix/store/}/init" "$desktop_home/bin/update-usb"; then
            echo "Expected update-usb to normalize squashfs verification paths relative to /nix/store." >&2
            ${pkgs.gnused}/bin/sed -n '180,230p' "$desktop_home/bin/update-usb" >&2
            exit 1
          fi

          if ! ${pkgs.gnugrep}/bin/grep -Fq "cryptsetup close --deferred" "$desktop_home/bin/update-usb"; then
            echo "Expected update-usb cleanup to defer mapper closure when immediate close stays busy." >&2
            ${pkgs.gnused}/bin/sed -n '500,580p' "$desktop_home/bin/update-usb" >&2
            exit 1
          fi

          if ! ${pkgs.gnugrep}/bin/grep -Fq "findmnt -Rrn" "$desktop_home/bin/update-usb"; then
            echo "Expected update-usb cleanup to recursively inspect /mnt before closing the mapper." >&2
            ${pkgs.gnused}/bin/sed -n '500,580p' "$desktop_home/bin/update-usb" >&2
            exit 1
          fi

          run_expect 0 gsr-record-help "$desktop_home/bin/gsr-record" --help
          assert_log_contains "Usage: gsr-record"

          run_expect 1 gsr-record-invalid-mode "$desktop_home/bin/gsr-record" nope
          assert_log_contains "Error: unknown mode 'nope'."

          run_expect 1 transmission-port-sync-invalid-port "$desktop_home/bin/transmission-port-sync" 0
          assert_log_contains "Error: port must be an integer between 1 and 65535."

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

          if ! ${pkgs.gnugrep}/bin/grep -Fq "app_refresh_duration_in_ms = 32" ${./modules/home/spotify.nix}; then
            echo "Expected spotify module to keep fast periodic app refresh polling." >&2
            ${pkgs.gnused}/bin/sed -n '100,170p' ${./modules/home/spotify.nix} >&2
            exit 1
          fi

          if ! ${pkgs.gnugrep}/bin/grep -Fq "client_id_command = { command =" ${./modules/home/spotify.nix}; then
            echo "Expected spotify module to resolve the client ID via a command." >&2
            ${pkgs.gnused}/bin/sed -n '100,170p' ${./modules/home/spotify.nix} >&2
            exit 1
          fi

          if ! ${pkgs.gnugrep}/bin/grep -Fq "spotify-player auth OAuth block not found" ${./modules/home/spotify.nix}; then
            echo "Expected spotify module to patch the upstream auth flow to honor the configured client ID." >&2
            ${pkgs.gnused}/bin/sed -n '1,140p' ${./modules/home/spotify.nix} >&2
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
    };

    nixosConfigurations = {
      desktop = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = {inherit inputs;};
        modules = [
          ./hosts/desktop/default.nix
          inputs.dms.nixosModules.greeter
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.backupFileExtension = "backup";
            home-manager.extraSpecialArgs = {
              # `hostType` is only a selector for lightweight shared-module
              # branches (small flags, package toggles, minor defaults). If a
              # branch starts needing host-owned services, session/runtime
              # files, or heavier patching, move it into dedicated host imports
              # instead of extending the shared contract here.
              inherit inputs;
              hostType = "desktop";
            };
            # sd-switch ensures user systemd services are properly enabled/started after activation
            home-manager.users.stefan.systemd.user.startServices = "sd-switch";
            home-manager.users.stefan = {
              imports = [
                ./hosts/desktop/home-manager.nix
                inputs.nixvim.homeModules.nixvim
              ];
            };
          }
        ];
      };

      usb = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = {inherit inputs;};
        modules = [
          ./hosts/usb/default.nix
          inputs.dms.nixosModules.greeter
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.backupFileExtension = "backup";
            home-manager.extraSpecialArgs = {
              # Keep USB on the same narrow `hostType` contract as desktop:
              # lightweight shared branches only, never host-owned runtime
              # behavior or larger service/session splits.
              inherit inputs;
              hostType = "usb";
            };
            # Keep USB user-service activation behavior in parity with desktop.
            home-manager.users.stefan.systemd.user.startServices = "sd-switch";
            home-manager.users.stefan = {
              imports = [
                ./hosts/usb/home-manager.nix
                inputs.nixvim.homeModules.nixvim
              ];
            };
          }
        ];
      };

      laptop = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = {inherit inputs;};
        modules = [
          ./hosts/laptop/default.nix
          inputs.dms.nixosModules.greeter
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.backupFileExtension = "backup";
            home-manager.extraSpecialArgs = {
              inherit inputs;
              hostType = "laptop";
            };
            home-manager.users.stefan.systemd.user.startServices = "sd-switch";
            home-manager.users.stefan = {
              imports = [
                ./hosts/laptop/home-manager.nix
                inputs.nixvim.homeModules.nixvim
              ];
            };
          }
        ];
      };
    };
  };
}
