{ pkgs, ... }: {
  # Vesktop desktop entry override: Vencord's "transparent" setting creates
  # a proper RGBA Electron window. The dank-discord.css bg vars need rgba()
  # to show the wallpaper through — this is handled by a Matugen template override.
  xdg.desktopEntries.vesktop = {
    name = "Vesktop";
    exec = "vesktop %U";
    icon = "vesktop";
    genericName = "Internet Messenger";
    categories = ["Network" "InstantMessaging" "Chat"];
  };
}
