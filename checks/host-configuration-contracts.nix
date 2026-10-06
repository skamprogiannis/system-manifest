{ctx}: {
  host-configuration-contracts = assert ctx.pkgs.lib.assertMsg ctx.spotifyPlayerRemoved
  "spotify_player and its service/auth migration must remain removed from every host.";
    ctx.pkgs.runCommand "host-configuration-contracts-check" {} ''
      touch "$out"
    '';
}
