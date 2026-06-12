{
  pkgs,
  inputs,
  ...
}: let
  spicePkgs = inputs.spicetify-nix.legacyPackages.${pkgs.stdenv.system};
in {
  programs.spicetify = {
    enable = true;
    theme =
      spicePkgs.themes.hazy
      // {
        additionalCss = builtins.readFile ./spicetify/hazy-system-manifest.css;
      };
    customColorScheme = {
      main = "0A0A0A";
      subtext = "E3E2E8";
      shadow = "000000";
      text = "F8F7FF";
      button = "B0C6FF";
      button-active = "C9D0FF";
      accent = "B0C6FF";
    };
  };
}
