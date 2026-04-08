{
  pkgs,
  lib,
  hostType ? null,
  ...
}: let
  vimiumCExtensionId = "hfjbmagddngcpeloejdejnfgbamkjaeg";
  vimiumCSeedLocalDir = ./brave/vimium-c/local-settings;
  vimiumCSeedSyncDir = ./brave/vimium-c/sync-settings;
  bravePreferencePatch = builtins.toJSON {
    intl = {
      accept_languages = "en,el";
      selected_languages = "en,el";
    };
    brave = {
      enable_window_closing_confirm = true;
      rewards.show_brave_rewards_button_in_location_bar = false;
      ai_chat = {
        show_toolbar_button = false;
        tab_organization_enabled = true;
      };
      wallet = {
        show_wallet_icon_on_toolbar = false;
        should_show_wallet_suggestion_badge = false;
      };
      brave_ads.should_allow_ads_subdivision_targeting = false;
      news."open-articles-in-new-tab" = true;
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
      accelerators."56215" = [
        "Alt+Backslash"
        "Control+Backslash"
      ];
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
      enable_spellchecking = true;
      show_home_button = false;
      # false = use system title bar and borders
      custom_chrome_frame = false;
    };
    account_values.browser.enable_spellchecking = true;
    privacy_sandbox = {
      first_party_sets_enabled = false;
      m1 = {
        ad_measurement_enabled = false;
        fledge_enabled = false;
        topics_enabled = false;
      };
    };
  };

  braveLocalStatePatch = builtins.toJSON {
    brave = {
      dont_ask_for_crash_reporting = true;
      p3a = {
        enabled = false;
        notice_acknowledged = true;
      };
      brave_ads.enabled_last_profile = false;
    };
  };

  braveEnabledFeatures =
    [
      "WebUIDarkMode"
      "VaapiVideoDecoder"
      "VaapiVideoEncoder"
    ]
    ++ lib.optionals (hostType != "usb") [
      "Vulkan"
      "UseSkiaRenderer"
    ];

  braveDisabledFeatures =
    [
      "HardwareMediaKeyHandling"
      "FullscreenAlertBubble"
    ]
    ++ lib.optionals (hostType == "usb") [
      "Vulkan"
      "UseSkiaRenderer"
    ];

  braveCommandLineArgs =
    [
      "--test-type"
      "--extensions-on-chrome-urls"
      "--ozone-platform-hint=auto"
      "--force-dark-mode"
      "--disable-features=${lib.concatStringsSep "," braveDisabledFeatures}"
      "--enable-features=${lib.concatStringsSep "," braveEnabledFeatures}"
    ]
    ++ lib.optionals (hostType != "usb") [
      "--use-gl=egl"
      "--enable-gpu-rasterization"
      "--enable-zero-copy"
    ]
    ++ lib.optionals (hostType == "usb") [
      "--disable-gpu-rasterization"
      "--disable-zero-copy"
    ];

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
    patch_json() {
      local target="$1"
      local patch="$2"
      mkdir -p "$(dirname "$target")"

      local tmp
      tmp=$(mktemp)
      if [ -s "$target" ] && ${pkgs.jq}/bin/jq empty "$target" >/dev/null 2>&1; then
        ${pkgs.jq}/bin/jq --argjson patch "$patch" '. * $patch' "$target" > "$tmp"
      else
        printf '%s\n' "$patch" > "$tmp"
      fi
      mv "$tmp" "$target"
    }

    patch_json "$HOME/.config/BraveSoftware/Brave-Browser/Default/Preferences" '${bravePreferencePatch}'
    patch_json "$HOME/.config/BraveSoftware/Brave-Browser/Local State" '${braveLocalStatePatch}'
  '';

  braveApplyState = pkgs.writeShellScriptBin "brave-apply-state" ''
    set -euo pipefail

    if ${pkgs.procps}/bin/pgrep -x brave >/dev/null || ${pkgs.procps}/bin/pgrep -x brave-browser >/dev/null; then
      echo "Brave is running; close it completely and run brave-apply-state again." >&2
      exit 1
    fi

    ${writeBravePreferences}
    ${writeVimiumCState}
    echo "Applied declarative Brave preferences and Vimium C state."
  '';
in {
  programs.brave = {
    enable = true;
    package = pkgs.brave.override {
      commandLineArgs = braveCommandLineArgs;
    };
    extensions = [
      {id = vimiumCExtensionId;}
      {id = "clngdbkpkpeebahjckkjfobafhncgmne";} # Stylus — custom CSS for catppuccin userstyles
    ];
  };

  # Declarative Brave profile patch + Vimium C state seeding.
  home.activation.vimiumCState = lib.hm.dag.entryAfter ["writeBoundary"] ''
    if ${pkgs.procps}/bin/pgrep -x brave >/dev/null || ${pkgs.procps}/bin/pgrep -x brave-browser >/dev/null; then
      echo "warning: Brave is running; skipping Brave preference/Vimium C sync this activation (close Brave and run brave-apply-state, or re-activate after closing Brave)" >&2
    else
      run ${writeBravePreferences}
      run ${writeVimiumCState}
    fi
  '';

  home.packages = [braveApplyState];

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
