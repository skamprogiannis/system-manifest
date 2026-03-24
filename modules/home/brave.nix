{
  pkgs,
  lib,
  ...
}: let
  vimiumCExtensionId = "hfjbmagddngcpeloejdejnfgbamkjaeg";
  vimiumCSeedLocalDir = ./brave/vimium-c/local-settings;
  vimiumCSeedSyncDir = ./brave/vimium-c/sync-settings;

  writeVimiumCState = pkgs.writeShellScript "brave-write-vimium-c-state" ''
    local_dir="$HOME/.config/BraveSoftware/Brave-Browser/Default/Local Extension Settings/${vimiumCExtensionId}"
    sync_dir="$HOME/.config/BraveSoftware/Brave-Browser/Default/Sync Extension Settings/${vimiumCExtensionId}"

    mkdir -p "$local_dir" "$sync_dir"
    rm -f "$local_dir"/* "$sync_dir"/*

    # Vimium C stores advanced options and keymaps in extension LevelDB state.
    # Seed both stores from declarative snapshots.
    cp -f ${vimiumCSeedLocalDir}/* "$local_dir/"
    cp -f ${vimiumCSeedSyncDir}/* "$sync_dir/"
  '';
in {
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
    extensions = [{id = vimiumCExtensionId;}];
  };

  # Brave does not expose managed policies for Vimium C advanced options.
  # Seed Vimium C's local/sync LevelDB state declaratively as best effort.
  home.activation.vimiumCState = lib.hm.dag.entryAfter ["writeBoundary"] ''
    if ${pkgs.procps}/bin/pgrep -x brave >/dev/null || ${pkgs.procps}/bin/pgrep -x brave-browser >/dev/null; then
      echo "warning: Brave is running; skipping Vimium C state sync this activation (close Brave and re-activate to apply)" >&2
    else
      run ${writeVimiumCState}
    fi
  '';

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
