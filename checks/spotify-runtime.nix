{ctx}: let
  inherit (ctx) desktopNixpkgsSpotify desktopSpicedSpotify desktopSpotifyPackage pkgs;
in {
  spotify-runtime =
    pkgs.runCommand "spotify-runtime-checks" {
      nativeBuildInputs = [pkgs.gnugrep];
    } ''
      set -euo pipefail
      if [ "${desktopSpotifyPackage}" != "${desktopNixpkgsSpotify}" ]; then
        echo "Spotify must use the complete current Nixpkgs package." >&2
        exit 1
      fi
      test -x ${desktopSpicedSpotify}/bin/spotify
      grep -Fxq 'Exec=spotify %U' ${desktopSpicedSpotify}/share/applications/spotify.desktop
      touch "$out"
    '';
}
