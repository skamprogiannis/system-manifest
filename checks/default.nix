{
  self,
  pkgs,
}: let
  ctx = import ./context.nix {inherit self pkgs;};
  registry = import ./registry.nix;

  mergeChecks = modules:
    builtins.foldl' (checks: module: checks // import module {inherit ctx;}) {} modules;

  checks = mergeChecks [
    ./hosts.nix
    ./usb-initrd-ordering.nix
    ./hyprland-keybinds.nix
    ./desktop-glass.nix
    ./desktop-runtime-config.nix
    ./neovim.nix
    ./wallpaper-runtime.nix
    ./codex-skills.nix
    ./script-smoke.nix
    ./shellcheck.nix
    ./ci-registry.nix
  ];

  registeredNames = registry.host ++ registry.support;
  exportedNames = builtins.attrNames checks;
  missingNames = builtins.filter (name: !(builtins.hasAttr name checks)) registeredNames;
  unregisteredNames = builtins.filter (name: !(builtins.elem name registeredNames)) exportedNames;
in
  if missingNames != []
  then throw "checks registry includes missing checks: ${builtins.concatStringsSep ", " missingNames}"
  else if unregisteredNames != []
  then throw "checks export unregistered checks: ${builtins.concatStringsSep ", " unregisteredNames}"
  else checks
