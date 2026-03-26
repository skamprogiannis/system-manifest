{
  pkgs,
  lib,
  ...
}: let
  vimiumCExtensionId = "hfjbmagddngcpeloejdejnfgbamkjaeg";
  vimiumCSeedLocalDir = ./brave/vimium-c/local-settings;
  vimiumCSeedSyncDir = ./brave/vimium-c/sync-settings;
  bravePreferencePatch = builtins.toJSON {
    brave = {
      rewards.show_brave_rewards_button_in_location_bar = false;
      ai_chat.show_toolbar_button = false;
      wallet.show_wallet_icon_on_toolbar = false;
      new_tab_page = {
        show_brave_news = false;
        show_rewards = false;
        show_together = false;
      };
      tabs = {
        always_hide_tab_close_button = true;
        hover_mode = 1;
        vertical_tabs_enabled = true;
        vertical_tabs_on_right = true;
        vertical_tabs_collapsed = true;
        vertical_tabs_expanded_state_per_window = true;
        vertical_tabs_floating_enabled = false;
        vertical_tabs_hide_completely_when_collapsed = false;
        vertical_tabs_show_scrollbar = false;
        vertical_tabs_show_title_on_window = false;
      };
      accelerators."56215" = ["Control+Backslash"];
      default_accelerators."56215" = [];
      sidebar = {
        hidden_built_in_items = [2];
        sidebar_items = [
          {
            built_in_item_type = 7;
            type = 0;
          }
          {
            built_in_item_type = 1;
            type = 0;
          }
          {
            built_in_item_type = 3;
            type = 0;
          }
          {
            built_in_item_type = 4;
            type = 0;
          }
        ];
      };
    };
    browser = {
      show_home_button = false;
      # false = use system title bar and borders
      custom_chrome_frame = false;
    };
  };

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

  writeBravePreferences = pkgs.writeShellScript "brave-write-preferences" ''
    pref_file="$HOME/.config/BraveSoftware/Brave-Browser/Default/Preferences"
    mkdir -p "$(dirname "$pref_file")"

    tmp=$(mktemp)
    if [ -s "$pref_file" ] && ${pkgs.jq}/bin/jq empty "$pref_file" >/dev/null 2>&1; then
      ${pkgs.jq}/bin/jq --argjson patch '${bravePreferencePatch}' '. * $patch' "$pref_file" > "$tmp"
    else
      printf '%s\n' '${bravePreferencePatch}' > "$tmp"
    fi
    mv "$tmp" "$pref_file"
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
        "--enable-features=UsePortalFileChooser,WebUIDarkMode,VaapiVideoDecoder,VaapiVideoEncoder,Vulkan,UseSkiaRenderer"
        "--use-gl=egl"
        "--enable-gpu-rasterization"
        "--enable-zero-copy"
      ];

    };
    extensions = [{id = vimiumCExtensionId;}];
  };

  # Declarative Brave profile patch + Vimium C state seeding.
  home.activation.vimiumCState = lib.hm.dag.entryAfter ["writeBoundary"] ''
    if ${pkgs.procps}/bin/pgrep -x brave >/dev/null || ${pkgs.procps}/bin/pgrep -x brave-browser >/dev/null; then
      echo "warning: Brave is running; skipping Brave preference/Vimium C sync this activation (close Brave and re-activate to apply)" >&2
    else
      run ${writeBravePreferences}
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
