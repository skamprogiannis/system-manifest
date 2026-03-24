{
  pkgs,
  config,
  lib,
  ...
}: let
  vesktopTransparentSettings = builtins.toJSON {
    minimizeToTray = true;
    arRPC = false;
    splashColor = "rgb(15,17,22)";
    splashBackground = "transparent";
    staticTitle = true;
    disableMinSize = false;
    hardwareAcceleration = true;
    discordBranch = "stable";
    tray = true;
    clickTrayToShowHide = false;
    customTitleBar = false;
    disableAutostart = false;
  };

  vesktopQuickCss = ''
    /* Liquid Glass: keep app chrome transparent so Hyprglass shows through. */
    :root,
    body,
    #app-mount,
    .app-2CXKsg,
    .bg-1QIAus,
    .layers-OrUESM,
    .layer-86YKbF {
      background: transparent !important;
      background-color: transparent !important;
    }

    /* Keep real content fully opaque for readability. */
    .contentRegion-3HkfJJ,
    .chat-2ZfjoI,
    .messagesWrapper-RpOMA3,
    .membersWrap-3NUR2t,
    .container-2o3qEW,
    .sidebar-1tnWFu,
    .standardSidebarView-E9Pc3j,
    .panels-3wFtMD {
      background-color: rgba(17, 19, 26, 0.94) !important;
      backdrop-filter: none !important;
    }
  '';

  vesktopLaunchWrapper = pkgs.writeShellScript "vesktop-launch" ''
    set -euo pipefail
    CFG="$HOME/.config/vesktop"
    SETTINGS_DIR="$CFG/settings"
    mkdir -p "$SETTINGS_DIR"

    # Keep settings persistent across Vesktop updates/restarts.
    printf '%s\n' '${vesktopTransparentSettings}' > "$CFG/settings.json"
    printf '%s\n' '${vesktopTransparentSettings}' > "$SETTINGS_DIR/settings.json"

    if [ ! -f "$SETTINGS_DIR/quickCss.css" ]; then
      cat > "$SETTINGS_DIR/quickCss.css" <<'EOF'
${vesktopQuickCss}
EOF
    fi

    exec ${pkgs.vesktop}/bin/vesktop "$@"
  '';
in {
  home.packages = [ pkgs.vesktop ];

  xdg.desktopEntries.vesktop = {
    name = "Vesktop";
    genericName = "Internet Messenger";
    comment = "Vesktop with transparent background wrapper";
    icon = "vesktop";
    terminal = false;
    categories = ["Network" "InstantMessaging"];
    startupNotify = true;
    exec = "${vesktopLaunchWrapper} %U";
    mimeType = ["x-scheme-handler/discord"];
  };
}
