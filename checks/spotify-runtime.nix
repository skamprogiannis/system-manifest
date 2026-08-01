{ctx}: let
  inherit
    (ctx)
    desktopHome
    desktopNixpkgsSpotify
    desktopSpicedSpotify
    desktopSpotifyDirectlyInstalled
    desktopSpotifyPackage
    pkgs
    ;
in {
  spotify-runtime =
    pkgs.runCommand "spotify-runtime-checks" {
      nativeBuildInputs = [
        pkgs.coreutils
        pkgs.findutils
        pkgs.gnugrep
      ];
    } ''
      set -euo pipefail

      if [ "${desktopSpotifyPackage}" != "${desktopNixpkgsSpotify}" ]; then
        echo "Spotify must use the complete current Nixpkgs package." >&2
        exit 1
      fi

      if [ ${builtins.toJSON desktopSpotifyDirectlyInstalled} != true ]; then
        echo "Spicetify Spotify must be installed directly without a launcher wrapper." >&2
        exit 1
      fi

      installed_spotify="$(readlink -f ${desktopHome}/bin/spotify)"
      spiced_spotify="$(readlink -f ${desktopSpicedSpotify}/bin/spotify)"
      if [ "$installed_spotify" != "$spiced_spotify" ]; then
        echo "The installed spotify command must resolve directly to Spicetify Spotify." >&2
        printf 'installed: %s\nexpected:  %s\n' "$installed_spotify" "$spiced_spotify" >&2
        exit 1
      fi

      if [ ! -x ${desktopSpicedSpotify}/bin/spotify ]; then
        echo "Spicetify Spotify does not provide the spotify command." >&2
        exit 1
      fi

      applications=${desktopHome}/share/applications
      desktop_file="$applications/spotify.desktop"
      if [ ! -f "$desktop_file" ]; then
        echo "Spicetify Spotify desktop entry is missing." >&2
        exit 1
      fi

      if [ "$(find "$applications" -maxdepth 1 -iname '*spotify*.desktop' | wc -l)" -ne 1 ]; then
        echo "Expected exactly one installed Spotify desktop entry." >&2
        find "$applications" -maxdepth 1 -iname '*spotify*.desktop' -print >&2
        exit 1
      fi

      if ! grep -Fxq 'Exec=spotify %U' "$desktop_file"; then
        echo "Spotify desktop entry must launch the direct spotify command." >&2
        grep '^Exec=' "$desktop_file" >&2 || true
        exit 1
      fi

      touch "$out"
    '';
}
