{ pkgs, ... }: {
  # Vesktop desktop entry override: adds --enable-transparent-visuals for
  # proper liquid glass (only backgrounds transparent, text/icons fully opaque).
  # Background colours in dank-discord.css are set to rgba() to use this.
  xdg.desktopEntries.vesktop = {
    name = "Vesktop";
    exec = "vesktop --enable-transparent-visuals %U";
    icon = "vesktop";
    genericName = "Internet Messenger";
    categories = ["Network" "InstantMessaging" "Chat"];
  };
}
