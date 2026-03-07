{
  config,
  pkgs,
  lib,
  ...
}: {
  programs.firefox = {
    enable = true;
    # Install Dracula theme via policy — forces installation without profile extension path issues
    policies = {
      ExtensionSettings = {
        "dracula-dark-colorscheme@draculatheme.com" = {
          install_url = "https://addons.mozilla.org/firefox/downloads/latest/dracula-dark-colorscheme/latest.xpi";
          installation_mode = "force_installed";
        };
      };
    };
    profiles.stefan = {
      isDefault = true;
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
