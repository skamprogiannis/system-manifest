{
  inputs,
  pkgs,
}: let
  base = import inputs.neovim-nixpkgs {
    system = pkgs.stdenv.hostPlatform.system;
    inherit (pkgs) config;
  };
  grammarPins = builtins.attrValues (builtins.fromJSON (builtins.readFile ./treesitter-grammar-pins.json));
  treesitterPackaging = base.path + "/pkgs/applications/editors/vim/plugins/nvim-treesitter";

  # The newest Treesitter queries need the parser revisions from the same source.
  # Reuse Nixpkgs' dependency and query packaging with the updated grammar pins.
  grammarDefinitions = builtins.readFile (treesitterPackaging + "/generated.nix");
  generated = assert base.lib.assertMsg
  (builtins.all (pin: builtins.replaceStrings [pin.oldRev] [""] grammarDefinitions != grammarDefinitions && builtins.replaceStrings [pin.oldHash] [""] grammarDefinitions != grammarDefinitions) grammarPins)
  "Refresh the Treesitter grammar pins when updating neovim-nixpkgs";
    builtins.toFile "treesitter-grammars.nix" (
      builtins.replaceStrings
      (base.lib.concatMap (pin: [pin.oldRev (builtins.substring 0 7 pin.oldRev) pin.oldHash]) grammarPins)
      (base.lib.concatMap (pin: [pin.rev (builtins.substring 0 7 pin.rev) pin.hash]) grammarPins)
      grammarDefinitions
    );
  overrides = builtins.toFile "treesitter-overrides.nix" (
    builtins.replaceStrings ["./generated.nix"] [generated]
    (builtins.readFile (treesitterPackaging + "/overrides.nix"))
  );
in
  base.extend (final: prev: {
    vimPlugins = prev.vimPlugins.extend (vimFinal: vimPrev: {
      nvim-treesitter = (vimPrev.nvim-treesitter.overrideAttrs {
        version = "0.10.0-unstable-2026-09-30";
        src = final.fetchFromGitHub {
          owner = "nvim-treesitter";
          repo = "nvim-treesitter";
          rev = "910fdf6f49e9dee7e7257c7d11a76b040fdfb9de";
          hash = "sha256-xmwLHE8JeSDyXeFggx1DzOPHc6OcNHngYEyuAcfI/Ck=";
        };
      }).overrideAttrs (final.callPackage overrides {} vimFinal vimPrev);
    });
  })
