{
  config,
  pkgs,
  lib,
  ...
}: {
  # Manage XDG User Directories (documents, downloads, music, etc.)
  # Lowercase paths are canonical in this repo so shell scripts, wallpaper
  # tooling, and app config all converge on one convention.
  xdg.userDirs = {
    enable = true;
    createDirectories = true;
    desktop = "${config.home.homeDirectory}/desktop";
    documents = "${config.home.homeDirectory}/documents";
    download = "${config.home.homeDirectory}/downloads";
    music = "${config.home.homeDirectory}/music";
    pictures = "${config.home.homeDirectory}/pictures";
    publicShare = "${config.home.homeDirectory}/public";
    templates = "${config.home.homeDirectory}/templates";
    videos = "${config.home.homeDirectory}/videos";
    extraConfig = {
      SCREENSHOTS = "${config.home.homeDirectory}/pictures/screenshots";
      SCREENCASTS = "${config.home.homeDirectory}/videos/screencasts";
      GAMES = "${config.home.homeDirectory}/games";
      PROJECTS = "${config.home.homeDirectory}/repositories";
      WALLPAPERS = "${config.home.homeDirectory}/wallpapers";
    };
  };

  # Allow unfree packages in ad-hoc nix commands (nix run, nix shell, etc.)
  # The NixOS-level nixpkgs.config.allowUnfree covers system and HM builds;
  # this file covers standalone nix CLI usage.
  xdg.configFile."nixpkgs/config.nix".text = "{ allowUnfree = true; }";

  # Migrate stray uppercase XDG dirs into the canonical lowercase locations
  # without overwriting any existing files in the lowercase targets.
  home.activation.cleanupLegacyUppercaseXdgDirs = lib.hm.dag.entryAfter ["writeBoundary"] ''
    migrate_legacy_dir() {
      local legacy_name="$1"
      local canonical_name="$2"
      local legacy_dir="$HOME/$legacy_name"
      local canonical_dir="$HOME/$canonical_name"

      [ -d "$legacy_dir" ] || return 0
      [ "$legacy_dir" = "$canonical_dir" ] && return 0

      mkdir -p "$canonical_dir"

      while IFS= read -r -d $'\0' item; do
        local base="''${item##*/}"
        if [ -e "$canonical_dir/$base" ]; then
          echo "Skipping legacy XDG item $item because $canonical_dir/$base already exists"
          continue
        fi

        echo "Migrating $item -> $canonical_dir/$base"
        ${pkgs.coreutils}/bin/mv "$item" "$canonical_dir/"
      done < <(${pkgs.findutils}/bin/find "$legacy_dir" -mindepth 1 -maxdepth 1 -print0)

      if [ -z "$(${pkgs.findutils}/bin/find "$legacy_dir" -mindepth 1 -print -quit)" ]; then
        ${pkgs.coreutils}/bin/rmdir "$legacy_dir"
      else
        echo "Leaving legacy directory $legacy_dir in place because it still has contents"
      fi
    }

    migrate_legacy_dir Desktop desktop
    migrate_legacy_dir Documents documents
    migrate_legacy_dir Downloads downloads
    migrate_legacy_dir Music music
    migrate_legacy_dir Pictures pictures
    migrate_legacy_dir Public public
    migrate_legacy_dir Templates templates
    migrate_legacy_dir Videos videos
  '';

  # Set custom icons for the directories using gio metadata.
  # Boot-time Home Manager activation runs before a user desktop session exists,
  # so skip this step until a real graphical session is available.
  home.activation.applyIcons = lib.hm.dag.entryAfter ["cleanupLegacyUppercaseXdgDirs"] ''
    if [ -n "''${DBUS_SESSION_BUS_ADDRESS-}" ] || [ -n "''${DISPLAY-}" ] || [ -n "''${WAYLAND_DISPLAY-}" ]; then
      function set_icon() {
        if [ -d "$1" ]; then
          ${pkgs.glib}/bin/gio set -t string "$1" metadata::custom-icon-name "$2"
        fi
      }

      set_icon "$HOME/desktop" "folder-desktop"
      set_icon "$HOME/documents" "folder-documents"
      set_icon "$HOME/downloads" "folder-download"
      set_icon "$HOME/music" "folder-music"
      set_icon "$HOME/pictures" "folder-pictures"
      set_icon "$HOME/public" "folder-public"
      set_icon "$HOME/templates" "folder-templates"
      set_icon "$HOME/videos" "folder-videos"
      set_icon "$HOME/games" "folder-games"
      set_icon "$HOME/repositories" "folder-code"
      set_icon "$HOME/pictures/screenshots" "applets-screenshooter"
      set_icon "$HOME/wallpapers" "preferences-desktop-wallpaper"
      set_icon "$HOME/videos/camera" "folder-videos"
      set_icon "$HOME/videos/screencasts" "camera-video"
      set_icon "$HOME/go" "folder-development"
      set_icon "$HOME/system-manifest" "folder-development"
      set_icon "$HOME/tabletop-games" "folder-books"
      set_icon "$HOME/scripts" "folder"
      set_icon "$HOME/wallpapers/.thumbnails" "folder-pictures"
    else
      echo "Skipping applyIcons: no graphical session available yet"
    fi
  '';
}
