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
      ];
    };
  };

  # Managed policy to force extensions in Brave
  home.file.".config/BraveSoftware/Brave-Browser/policies/managed/extensions.json".text = builtins.toJSON {
    ExtensionInstallForcelist = [
      "pdeffakfmcdnjjafophphgmddmigpejh;https://clients2.google.com/service/update2/crx" # PearPass
      "hfjnimnojonndamibeoponojhlghnbpl;https://clients2.google.com/service/update2/crx" # Vimium C
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
