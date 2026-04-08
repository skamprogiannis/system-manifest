{
  pkgs,
  config,
  lib,
  inputs,
  ...
}: let
  common = import ./common.nix {inherit pkgs inputs;};
  sharedArgs =
    {
      inherit pkgs config lib inputs;
    }
    // common;
in {
  imports = [
    (import ./services.nix sharedArgs)
    (import ./engine-sync.nix sharedArgs)
    (import ./hook.nix sharedArgs)
    (import ./restore.nix sharedArgs)
    (import ./library-sync.nix sharedArgs)
  ];
}
