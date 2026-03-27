# Shared path constants and helpers for wallpaper scripts.
# Sourced by wallpaper-apply, wallpaper-hook, and wallpaper-engine-sync.
{pkgs}: {
  # All scripts share these base paths.
  constants = ''
    MAP_FILE="$HOME/.cache/we-wallpaper-map.json"
    WE_ASSETS="$HOME/games/SteamLibrary/steamapps/common/wallpaper_engine/assets"
    WE_WORKSHOP="$HOME/games/SteamLibrary/steamapps/workshop/content/431960"
    WE_DEFAULTS_ROOT="$HOME/games/SteamLibrary/steamapps/common/wallpaper_engine/projects/defaultprojects"
    WALL_DIR="$HOME/wallpapers/.wallpaper-engine"
  '';

  # Strip trailing slashes and resolve symlinks.
  normalizeDir = ''
    normalize_dir() {
      ${pkgs.coreutils}/bin/realpath "$1" | ${pkgs.gnused}/bin/sed 's:/*$::'
    }
  '';
}
