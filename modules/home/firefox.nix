{
  config,
  pkgs,
  ...
}: {
  programs.firefox = {
    enable = true;
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
        # Required for userChrome.css to take effect
        "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
      };
      userChrome = ''
        /* Liquid glass: transparent browser chrome, web content stays opaque */
        #main-window, #browser {
          background-color: transparent !important;
        }
        #navigator-toolbox {
          background-color: rgba(30, 15, 14, 0.75) !important;
          border-bottom: 1px solid rgba(250, 220, 217, 0.1) !important;
        }
        .tabbrowser-tab .tab-background {
          background-color: rgba(30, 15, 14, 0.50) !important;
        }
        .tabbrowser-tab[selected="true"] .tab-background {
          background-color: rgba(30, 15, 14, 0.85) !important;
        }
      '';
    };
  };
}
