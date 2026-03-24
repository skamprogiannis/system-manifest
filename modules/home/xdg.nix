{
  config,
  pkgs,
  lib,
  ...
}: let
  yaziOpenWrapper = pkgs.writeShellScript "yazi-open-wrapper" ''
    set -euo pipefail

    target="''${1:-$HOME}"

    if [ "''${target#file://}" != "$target" ]; then
      target=$(${pkgs.python3}/bin/python3 - "$target" <<'PY'
import sys
from urllib.parse import unquote, urlparse

uri = sys.argv[1]
parsed = urlparse(uri)
path = parsed.path or ""
print(unquote(path))
PY
      )
    fi

    if [ ! -e "$target" ]; then
      target="$HOME"
    fi

    exec ${pkgs.ghostty}/bin/ghostty -e ${pkgs.yazi}/bin/yazi "$target"
  '';
in {
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
      SCREENSHOTS = "${config.home.homeDirectory}/pictures/screenshots";
      SCREENCASTS = "${config.home.homeDirectory}/videos/screencasts";
      GAMES = "${config.home.homeDirectory}/games";
      PROJECTS = "${config.home.homeDirectory}/repositories";
      WALLPAPERS = "${config.home.homeDirectory}/wallpapers";
    };
  };

  # Set custom icons for the directories using gio metadata
  home.activation.applyIcons = lib.hm.dag.entryAfter ["writeBoundary"] ''
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
  '';

  home.file.".config/xdg-desktop-portal-termfilechooser/config".text = ''
    [filechooser]
    cmd=${config.home.homeDirectory}/.config/xdg-desktop-portal-termfilechooser/ghostty-yazi-wrapper.sh
    default_dir=$HOME
    open_mode=suggested
    save_mode=suggested
  '';

  home.file.".config/xdg-desktop-portal-termfilechooser/ghostty-yazi-wrapper.sh" = {
    executable = true;
    text = ''
      #!${pkgs.bash}/bin/bash
      set -e

      multiple="$1"
      directory="$2"
      save="$3"
      path="$4"
      out="$5"

      if [ "$save" = "1" ]; then
          set -- --chooser-file="$out" "$path"
      elif [ "$directory" = "1" ]; then
          set -- --chooser-file="$out" --cwd-file="$out"".1" "$path"
      elif [ "$multiple" = "1" ]; then
          set -- --chooser-file="$out" "$path"
      else
          set -- --chooser-file="$out" "$path"
      fi

      command="${pkgs.ghostty}/bin/ghostty -e ${pkgs.yazi}/bin/yazi"
      for arg in "$@"; do
          escaped=$(printf "%s" "$arg" | sed 's/"/\\"/g')
          command="$command \"$escaped\""
      done

      sh -c "$command"

      if [ "$directory" = "1" ]; then
          if [ ! -s "$out" ] && [ -s "$out"".1" ]; then
              cat "$out"".1" > "$out"
              rm "$out"".1"
          else
              rm "$out"".1"
          fi
      fi
    '';
  };

  xdg.desktopEntries.yazi-opener = {
    name = "Yazi File Manager";
    genericName = "Terminal File Manager";
    comment = "Open files and folders in Yazi";
    exec = "${yaziOpenWrapper} %U";
    terminal = false;
    categories = ["Utility" "System" "FileManager"];
    noDisplay = false;
    mimeType = [
      "inode/directory"
      "x-directory/normal"
      "x-scheme-handler/file"
    ];
  };

  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "inode/directory" = ["yazi-opener.desktop"];
      "x-directory/normal" = ["yazi-opener.desktop"];
      "x-scheme-handler/file" = ["yazi-opener.desktop"];
    };
  };
}
