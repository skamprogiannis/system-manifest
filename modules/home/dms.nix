{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: {
  imports = [
    inputs.dms.homeModules.dank-material-shell
  ];

  programs.dank-material-shell = {
    enable = true;
    systemd.enable = true;
    enableSystemMonitoring = true;
    enableDynamicTheming = true;
    enableClipboardPaste = true;
    enableCalendarEvents = false;
    enableVPN = true;
    enableAudioWavelength = true;
    settings = {
      # --- THEME & COLOR ---
      currentThemeName = "dynamic";
      currentThemeCategory = "dynamic";
      matugenScheme = "scheme-fidelity";
      matugenPaletteFidelity = 1;

      # --- CURSOR ---
      cursorSettings = {
        theme = "Dracula-cursors";
        size = 24;
        hyprland = {
          hideOnKeyPress = true;
          hideOnTouch = false;
          inactiveTimeout = 5;
        };
      };

      # --- GENERAL ---
      showSeconds = true;
      useAutoLocation = true;
      use24HourClock = true;
      cornerRadius = 12;

      # --- NOTIFICATIONS ---
      notificationTimeoutNormal = 10000;
      notificationTimeoutLow = 5000;
      notificationHistorySaveLow = false;

      # --- MATUGEN TEMPLATES ---
      runDmsMatugenTemplates = true;
      runUserMatugenTemplates = true;
      matugenTemplateGtk = true;
      matugenTemplateHyprland = true;
      matugenTemplateFirefox = true;
      matugenTemplateVesktop = true;
      matugenTemplateGhostty = true;
      matugenTemplateNeovim = true;
      matugenTemplateDgop = true;
      matugenTemplateKcolorscheme = true;
      matugenTemplateNiri = false;
      matugenTemplateMangowc = false;
      matugenTemplateQt5ct = false;
      matugenTemplateQt6ct = false;
      matugenTemplatePywalfox = false;
      matugenTemplateZenBrowser = false;
      matugenTemplateEquibop = false;
      matugenTemplateKitty = false;
      matugenTemplateFoot = false;
      matugenTemplateAlacritty = false;
      matugenTemplateWezterm = false;
      matugenTemplateVscode = false;
      matugenTemplateEmacs = false;
    };
  };
}
