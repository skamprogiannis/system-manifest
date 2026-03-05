{ pkgs, ... }: {
  # Translucence theme — deployed as a local Vencord theme file.
  # Enable it once in Vesktop: Settings → Vencord → Themes → Local Themes.
  home.file.".config/vesktop/themes/Translucence.theme.css".text = ''
    /**
     * @name Translucence
     * @version 1.0.7
     * @description A translucent/frosted glass Discord theme
     * @author CapnKitten
     * @source https://github.com/CapnKitten/Translucence
     */

    @import url(https://capnkitten.github.io/BetterDiscord/Themes/Translucence/css/source.css);
  '';
}
