{
  config,
  pkgs,
  ...
}: {
  programs.firefox = {
    enable = true;
    # Add privacy-focused settings or extensions here if desired
    profiles.stefan = {
      isDefault = true;
      settings = {
        "browser.startup.homepage" = "about:blank";
        "browser.search.region" = "GR";
        "browser.search.isUS" = false;
        "distribution.searchplugins.defaultLocale" = "en-US";
        "general.useragent.locale" = "en-US";
        # Disable Pocket
        "extensions.pocket.enabled" = false;
      };
    };
  };
}
