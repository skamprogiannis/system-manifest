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
    systemd = {
      enable = true;
      target = "hyprland-session.target";
    };
    enableSystemMonitoring = true;
    enableDynamicTheming = true;
    enableClipboardPaste = true;
    enableCalendarEvents = false;
    enableVPN = true;
    enableAudioWavelength = true;
    clipboardSettings = {
      maxPinned = 10;
      autoClearDays = 1;
    };
    settings = {
      # --- THEME & COLOR ---
      currentThemeName = "dynamic";
      currentThemeCategory = "dynamic";
      matugenScheme = "scheme-fidelity";
      matugenPaletteFidelity = 1;

      # --- CURSOR ---
      cursorSettings = {
        theme = config.home.pointerCursor.name;
        size = config.home.pointerCursor.size;
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
      enablePerModeWallpapers = false;
      muxType = "zellij";
      muxSessionFilter = "";
      clipboardEnterToPaste = false;
      lockScreenShowProfileImage = true;
      greeterRememberLastSession = true;
      greeterRememberLastUser = true;

      # --- POWER & SLEEP ---
      acMonitorTimeout = 600;
      acLockTimeout = 1800;
      acSuspendTimeout = 3600;
      lockBeforeSuspend = true;

      # --- LOCK SCREEN ---
      fadeToLockEnabled = true;
      fadeToDpmsEnabled = true;

      # --- NOTIFICATIONS ---
      notificationTimeoutNormal = 10000;
      notificationTimeoutLow = 5000;
      notificationHistorySaveLow = false;

      # --- MATUGEN TEMPLATES ---
      runDmsMatugenTemplates = true;
      runUserMatugenTemplates = true;
      matugenTemplateGtk = true;
      matugenTemplateHyprland = true;
      matugenTemplateFirefox = false;
      matugenTemplateVesktop = true;
      matugenTemplateGhostty = false;
      matugenTemplateNeovim = true;
      matugenTemplateZellij = true;
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

  # Ensure dms CLI can always resolve shell.qml (including greeter-sync calls
  # started by DMS UI paths that don't use the profile wrapper).
  home.file.".config/quickshell/dms".source =
    "${config.programs.dank-material-shell.package}/share/quickshell/dms";

  # Keep built-in analog devices hidden by default without making session.json
  # immutable/read-only. Use stable PipeWire node names so sink/source can be
  # hidden independently.
  home.activation.dmsAudioDeviceVisibility = lib.hm.dag.entryAfter ["writeBoundary"] ''
    session_file="$HOME/.local/state/DankMaterialShell/session.json"
    mkdir -p "$(dirname "$session_file")"

    if [ -s "$session_file" ] && ${pkgs.jq}/bin/jq empty "$session_file" >/dev/null 2>&1; then
      :
    else
      printf '%s\n' '{}' > "$session_file"
    fi

    tmp_file=$(mktemp)
    ${pkgs.jq}/bin/jq \
      --argjson hiddenOutput '["alsa_output.pci-0000_00_1f.3.analog-stereo"]' \
      --argjson hiddenInput '["alsa_input.pci-0000_00_1f.3.analog-stereo"]' \
      '.hiddenOutputDeviceNames = (((.hiddenOutputDeviceNames // []) + $hiddenOutput) | unique)
       | .hiddenInputDeviceNames = (((.hiddenInputDeviceNames // []) + $hiddenInput) | unique)' \
      "$session_file" > "$tmp_file"
    mv "$tmp_file" "$session_file"
  '';
}
