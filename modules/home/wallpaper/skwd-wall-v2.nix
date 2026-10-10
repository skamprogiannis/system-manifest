{
  config,
  inputs,
  lib,
  pkgs,
  ...
}: let
  # The preview renderer supports these roles even before a full scheme exists.
  previewRoles = [
    "background"
    "error"
    "error_container"
    "inverse_on_surface"
    "inverse_primary"
    "inverse_surface"
    "on_background"
    "on_error"
    "on_error_container"
    "on_primary"
    "on_primary_container"
    "on_secondary"
    "on_secondary_container"
    "on_surface"
    "on_surface_variant"
    "on_tertiary"
    "on_tertiary_container"
    "outline"
    "outline_variant"
    "primary"
    "primary_container"
    "scrim"
    "secondary"
    "secondary_container"
    "shadow"
    "surface"
    "surface_bright"
    "surface_container"
    "surface_container_high"
    "surface_container_highest"
    "surface_container_low"
    "surface_container_lowest"
    "surface_dim"
    "surface_variant"
    "tertiary"
    "tertiary_container"
  ];
  previewTemplate = pkgs.writeText "dms-preview.json" (builtins.toJSON {
    colors =
      lib.genAttrs ["dark" "light"] (mode:
        lib.genAttrs previewRoles (role: "{{colors.${role}.${mode}.hex}}"));
  });
  wallpaperSync = pkgs.writeShellApplication {
    name = "wallpaper-sync";
    runtimeInputs = [pkgs.bash pkgs.coreutils pkgs.matugen];
    text = ''
      export WALLPAPER_SYNC_DMS="''${WALLPAPER_SYNC_DMS:-${config.programs.dank-material-shell.package}/bin/dms}"
      export WALLPAPER_SYNC_SHELL_DIR="''${WALLPAPER_SYNC_SHELL_DIR:-${config.programs.dank-material-shell.package}/share/quickshell/dms}"
      export WALLPAPER_SYNC_MAGICK="''${WALLPAPER_SYNC_MAGICK:-${pkgs.imagemagick}/bin/magick}"
      export WALLPAPER_SYNC_HELM="''${WALLPAPER_SYNC_HELM:-${inputs.skwd-wall.packages.${pkgs.stdenv.hostPlatform.system}.deck}/bin/skwd-helm}"
      exec ${pkgs.python3}/bin/python3 ${./wallpaper-sync.py} "$@"
    '';
  };
  managedTheme = pkgs.writeText "skwd-wall-v2-theme.json" (builtins.toJSON {
    features.matugen = true;
    theme = {
      policy = "wallpaper";
      authority = "skwd";
      engine = "matugen";
      targets = ["dms"];
    };
    integrations = [
      {
        name = "system-manifest-dms-preview";
        template = "${previewTemplate}";
        output = "${config.xdg.cacheHome}/DankMaterialShell/dms-colors.json";
        livePreview = true;
      }
    ];
  });
in {
  home.packages = [wallpaperSync];
  home.sessionVariables.DMS_DISABLE_MATUGEN = "1";

  systemd.user.services.dms.Service = {
    Environment = ["DMS_DISABLE_MATUGEN=1"];
    ExecStartPre = ["${wallpaperSync}/bin/wallpaper-sync prepare"];
  };

  systemd.user.services.wallpaper-sync = {
    Unit = {
      Description = "Sync the applied wallpaper and palette to DMS and the greeter";
      # Explicit target ordering avoids the target implicitly waiting for us.
      After = ["hyprland-session.target" "skwd-walld.service" "dms.service"];
      Wants = ["skwd-walld.service" "dms.service"];
      PartOf = ["hyprland-session.target"];
    };
    Service = {
      ExecStart = "${wallpaperSync}/bin/wallpaper-sync watch";
      Restart = "on-failure";
      RestartSec = 2;
    };
    Install.WantedBy = ["hyprland-session.target"];
  };

  # skwd-wall v2 owns wallpaper-derived colour generation. Keep the rest of its
  # runtime/UI configuration user-editable while declaratively pinning the
  # shared colour pipeline used by DMS and Vesktop. Seed missing Steam fields
  # from private local v1 state without placing credentials in the Nix store.
  home.activation.configureSkwdWallV2Theming = lib.hm.dag.entryAfter ["writeBoundary"] ''
    ${pkgs.python3}/bin/python3 ${./configure-v2.py} --home "$HOME" --managed-theme ${managedTheme}
  '';
}
