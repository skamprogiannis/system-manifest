{
  config,
  lib,
  ...
}: let
  spotifyCacheDir = "${config.xdg.cacheHome}/spotify-player";
  migrationStamp = "${config.xdg.stateHome}/system-manifest/spotify-no-client-id-v1";
in {
  home.activation.spotifyUsbAuthMigration = lib.hm.dag.entryAfter ["writeBoundary"] ''
    stamp_file="${migrationStamp}"

    if [ ! -e "$stamp_file" ] && [ -e "${spotifyCacheDir}/user_client_token.json" -o -e "${spotifyCacheDir}/credentials.json" ]; then
      mkdir -p "$(dirname "$stamp_file")"
      rm -f "${spotifyCacheDir}/credentials.json" "${spotifyCacheDir}/user_client_token.json"
      printf '1\n' > "$stamp_file"
      echo "spotify_player: cleared legacy cached auth so USB upgrades pick up the current config" >&2
    fi
  '';
}
