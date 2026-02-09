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
    extensions = [
      {id = "pdeffakfmcdnjjafophphgmddmigpejh";} # PearPass
      {id = "hfjnimnojonndamibeoponojhlghnbpl";} # Vimium C
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
}
