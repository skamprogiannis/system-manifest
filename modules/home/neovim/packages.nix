{
  inputs,
  pkgs,
}:
import inputs.neovim-nixpkgs {
  system = pkgs.stdenv.hostPlatform.system;
  inherit (pkgs) config;
}
