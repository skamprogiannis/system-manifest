{
  config,
  pkgs,
  lib,
  ...
}: {
  # Manage XDG User Directories (documents, downloads, music, etc.)
  # This ensures they are created and managed declaratively.
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
      XDG_SCREENSHOTS_DIR = "${config.home.homeDirectory}/pictures/screenshots";
      XDG_GAMES_DIR = "${config.home.homeDirectory}/games";
      XDG_PROJECTS_DIR = "${config.home.homeDirectory}/repositories";
      XDG_WALLPAPERS_DIR = "${config.home.homeDirectory}/pictures/wallpapers";
    };
  };

  # Set custom icons for the directories using gio metadata
  home.activation.applyIcons = lib.hm.dag.entryAfter ["writeBoundary"] ''
    function set_icon() {
      if [ -d "$1" ]; then
        ${pkgs.glib}/bin/gio set -t string "$1" metadata::custom-icon-name "$2"
      fi
    }

    set_icon "$HOME/desktop" "user-desktop"
    set_icon "$HOME/documents" "folder-documents"
    set_icon "$HOME/downloads" "folder-download"
    set_icon "$HOME/music" "folder-music"
    set_icon "$HOME/pictures" "folder-pictures"
    set_icon "$HOME/public" "folder-publicshare"
    set_icon "$HOME/templates" "folder-templates"
    set_icon "$HOME/videos" "folder-videos"
    set_icon "$HOME/games" "folder-games"
    set_icon "$HOME/repositories" "folder-development"
    set_icon "$HOME/pictures/screenshots" "applets-screenshooter"
    set_icon "$HOME/pictures/wallpapers" "preferences-desktop-wallpaper"
    set_icon "$HOME/system_manifest" "folder-development"
    set_icon "$HOME/tabletop_games" "folder-documents"
  '';
}
