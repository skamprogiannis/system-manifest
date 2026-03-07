{ pkgs, ... }: let
  vesktop-launch = pkgs.writeShellScript "vesktop-launch" ''
    # Ensure Electron RGBA transparency is enabled before each launch.
    # Vesktop overwrites this setting to false on exit.
    ${pkgs.gnused}/bin/sed -i 's/"transparent": false/"transparent": true/' \
      "$HOME/.config/vesktop/settings/settings.json" 2>/dev/null
    exec ${pkgs.vesktop}/bin/vesktop "$@"
  '';
in {
  # Vesktop wrapper: patches settings.json to enable Electron RGBA transparency
  # before each launch. Combined with Translucence CSS theme, this gives proper
  # liquid glass — wallpaper shows through panels, text stays opaque.
  xdg.desktopEntries.vesktop = {
    name = "Vesktop";
    exec = "${vesktop-launch} %U";
    icon = "vesktop";
    genericName = "Internet Messenger";
    categories = ["Network" "InstantMessaging" "Chat"];
  };
}
