{
  config,
  pkgs,
  lib,
  ...
}: {
  programs.firefox = {
    enable = true;
    profiles.stefan = {
      isDefault = true;
      extensions = [
        (pkgs.fetchFirefoxAddon {
          name = "dracula-dark-colorscheme";
          url = "https://addons.mozilla.org/firefox/downloads/latest/dracula-dark-colorscheme/latest.xpi";
          hash = "sha256-ERscK8dz+wr1YsLIWTQ+WdipDRpEYRlpf4gNF3ElPlk=";
        })
      ];
      settings = {
        "browser.startup.homepage" = "about:blank";
        "browser.search.region" = "GR";
        "browser.search.isUS" = false;
        "distribution.searchplugins.defaultLocale" = "en-US";
        "general.useragent.locale" = "en-US";
        "extensions.pocket.enabled" = false;
        "gfx.webrender.all" = true;
        "media.ffmpeg.vaapi.enabled" = true;
        "media.hardware-video-decoding.force-enabled" = true;
        "layers.acceleration.force-enabled" = true;
      };
    };
  };
}
