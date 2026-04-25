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

    spotify-player = {
      url = "github:aome510/spotify-player";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    skwd-wall = {
      url = "github:liixini/skwd-wall";
    };

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
      shellcheckScripts = [
        "${desktopHome}/bin/copilot-sessions-sync"
        "${desktopHome}/bin/gsr-record"
        "${desktopHome}/bin/hypr-nav"
        "${desktopHome}/bin/hypr-quit-active"
        "${desktopHome}/bin/screenshot-path-copy"
        "${desktopHome}/bin/setup-persistent-usb"
        "${desktopHome}/bin/spotify_player"
        "${desktopHome}/bin/transmission-port-sync"
        "${desktopHome}/bin/update-usb"
        "${desktopHome}/bin/zellij-sessionizer"
        "${usbHome}/bin/spotify_player"
      ];
    in {
      desktop = self.nixosConfigurations.desktop.config.system.build.toplevel;
      usb = self.nixosConfigurations.usb.config.system.build.toplevel;
      script-smoke = pkgs.runCommand "script-smoke-checks" {
        nativeBuildInputs = [
          pkgs.gnugrep
          pkgs.gnused
        ];
      } ''
        set -euo pipefail

        desktop_home="${desktopHome}"
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

        run_expect 0 setup-persistent-usb-help "$desktop_home/bin/setup-persistent-usb" --help
        assert_log_contains "Creates a fresh persistent NixOS USB"

        run_expect 1 update-usb-invalid-mode "$desktop_home/bin/update-usb" --mode nope
        assert_log_contains "Error: invalid mode 'nope'."

        if ! ${pkgs.gnugrep}/bin/grep -Fq "#/nix/}/init" "$desktop_home/bin/update-usb"; then
          echo "Expected update-usb to normalize squashfs verification paths relative to /nix." >&2
          ${pkgs.gnused}/bin/sed -n '180,230p' "$desktop_home/bin/update-usb" >&2
          exit 1
        fi

        run_expect 0 gsr-record-help "$desktop_home/bin/gsr-record" --help
        assert_log_contains "Usage: gsr-record"

        run_expect 1 gsr-record-invalid-mode "$desktop_home/bin/gsr-record" nope
        assert_log_contains "Error: unknown mode 'nope'."

        run_expect 1 transmission-port-sync-invalid-port "$desktop_home/bin/transmission-port-sync" 0
        assert_log_contains "Error: port must be an integer between 1 and 65535."

        touch "$out"
      '';
      shellcheck = pkgs.runCommand "shellcheck-scripts" {
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
              # Use hostType only for lightweight shared-module branches.
              # Keep heavier host-specific patching in dedicated host modules.
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
    };
  };
}
