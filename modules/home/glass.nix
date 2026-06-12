{
  vesktop = {
    sidebarSurfacePercent = 45;
    mainSurfacePercent = 35;
    messageSurfacePercent = 41;
    cardSurfacePercent = 43;
    cardHoverSurfacePercent = 51;
    cardSelectSurfacePercent = 59;
    textareaRgb = "22, 24, 31";
    textareaAlpha = "0.57";
    textareaFocusAlpha = "0.65";
    settingsSurfacePercent = 63;
    settingsBlurPx = 20;
    settingsSaturate = "1.12";
    settingsBorderPercent = 26;
    popoutSurfacePercent = 55;
    popoutBlurPx = 18;
    popoutSaturate = "1.1";
    popoutBorderPercent = 20;
    mentionSurfacePercent = 47;
  };

  ghostty = {
    backgroundOpacity = 0.40;
    backgroundBlur = true;
    minimumContrast = 1.15;
  };

  hyprland.blur = {
    size = 3;
    passes = 2;
    noise = 0.02;
    contrast = 0.9;
    ignoreOpacity = true;
    xray = false;
    newOptimizations = true;
    popups = true;
    popupsIgnoreAlpha = 0.2;
  };

  dms = {
    barTransparency = 0.35;
    barWidgetTransparency = 0.55;
    popupTransparency = 0.55;
    notepadTransparency = 0.60;
    systemMonitorTransparency = 0.60;
    layerIgnoreAlpha = 0.2;
    blurNamespaces = [
      "bar"
      "spotlight"
      "app-launcher"
      "notification-popup"
      "toast"
      "osd"
      "control-center"
      "notification-center-popout"
      "notification-center-modal"
      "clipboard-popout"
      "clipboard-context-menu"
      "dash"
      "process-list-popout"
      "workspace-overview"
      "niri-overview-spotlight"
      "power-menu"
      "wifi-qrcode"
      "color-picker"
      "layout"
      "system-update"
      "battery"
      "vpn"
      "bluetooth-pairing"
      "input-modal"
      "confirm-modal"
      "mux"
      "filebrowser"
      "network-info"
      "keybinds"
      "dock-context-menu"
      "tray-overflow-menu"
      "tray-menu-window"
      "notepad-context-menu"
      "modal"
      "slideout"
    ];
  };

  spicetify.hazy = {
    backdropLighter = "rgba(0, 0, 0, 0.30)";
    backdrop = "rgba(0, 0, 0, 0.35)";
    backdropDarker = "rgba(0, 0, 0, 0.43)";
    backdropDark = "rgba(0, 0, 0, 0.60)";
    backdropLight = "rgb(68 68 68 / 30%)";
    cardOpacity = "0.43";
    albumArtBlurPx = 8;
    albumArtContrastPercent = 85;
    albumArtSaturationPercent = 85;
    albumArtBrightnessPercent = 100;
    albumArtOpacity = "0.45";
    panelBlurPx = 8;
    popoverBlurPx = 8;
  };

  gtk = {
    popoverBackground = "#11111b";
    popoverAlpha = "0.80";
    popoverBorder = "#cdd6f4";
    popoverBorderAlpha = "0.05";
    popoverShadow = "#000000";
    popoverShadowAlpha = "0.32";
  };
}
