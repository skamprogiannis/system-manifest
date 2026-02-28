{
  config,
  pkgs,
  ...
}: {
  programs.brave = {
    enable = true;
    package = pkgs.brave.override {
      commandLineArgs = [
        "--disable-features=HardwareMediaKeyHandling"
        "--test-type"
        "--extensions-on-chrome-urls"
      ];
    };
    extensions = [
      {id = "dbepggeogbaibhgnhhndojpepiihcmeb";} # Vimium C
      {id = "pdeffakfmcdnjjafophphgmddmigpejh";} # PearPass
    ];
  };

  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "text/html" = "brave-browser.desktop";
      "x-scheme-handler/http" = "brave-browser.desktop";
      "x-scheme-handler/https" = "brave-browser.desktop";
      "x-scheme-handler/about" = "brave-browser.desktop";
      "x-scheme-handler/unknown" = "brave-browser.desktop";
    };
  };

  # Hide the duplicate Brave entry
  xdg.desktopEntries."com.brave.Browser" = {
    name = "Brave Web Browser";
    exec = "brave";
    noDisplay = true;
  };
}
