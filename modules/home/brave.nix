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
        "--ozone-platform-hint=auto"
        "--force-dark-mode"
        "--enable-features=WebUIDarkMode,VaapiVideoDecoder,VaapiVideoEncoder,Vulkan,UseSkiaRenderer"
        "--use-gl=egl"
        "--enable-gpu-rasterization"
        "--enable-zero-copy"
      ];

    };
    extensions = [
      {id = "dbepggeogbaibhgnhhndojpepiihcmeb";} # Vimium C
      {id = "pdeffakfmcdnjjafophphgmddmigpejh";} # PearPass
      {id = "klmoijkddehdpobmgicjlcidiijfngig";} # Dracula theme
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
