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

    checks.${system} = import ./checks {inherit self pkgs;};

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
