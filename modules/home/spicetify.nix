{
  pkgs,
  inputs,
  ...
}: let
  spicePkgs = inputs.spicetify-nix.legacyPackages.${pkgs.stdenv.system};
in {
  programs.spicetify = {
    enable = true;
    theme = spicePkgs.themes.hazy;
    extraCommands = ''
          substituteInPlace Extensions/hazy.js \
            --replace-fail \
              '  const defImage = "https://i.imgur.com/Wl2D0h0.png";' \
              '  if (window.__systemManifestHazyLoaded) return;
      window.__systemManifestHazyLoaded = true;

      const defImage = "https://i.imgur.com/Wl2D0h0.png";'
    '';
  };
}
