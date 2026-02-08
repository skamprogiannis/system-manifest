{
  config,
  pkgs,
  ...
}: {
  home.packages = with pkgs; [
    (brave.override {
      commandLineArgs = [
        "--disable-features=HardwareMediaKeyHandling"
      ];
    })
  ];

  # Declarative Brave Extensions
  # PearPass: pdeffakfmcdnjjafophphgmddmigpejh
  # Vimium: dbepclhmjogiooabhcaphlbebaymabck
  programs.brave = {
    enable = true;
    extensions = [
      {id = "pdeffakfmcdnjjafophphgmddmigpejh";} # PearPass
      {id = "dbepclhmjogiooabhcaphlbebaymabck";} # Vimium
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
