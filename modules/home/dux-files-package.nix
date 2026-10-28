{
  inputs,
  pkgs,
}: let
  glass = import ./glass.nix;
  package = inputs.dux-files.packages.${pkgs.stdenv.hostPlatform.system}.dux-files;
in
  package.overrideAttrs (old: {
    # Dux 2.0 embeds opaque QML surfaces. Apply the shared glass values to the
    # embedded copy, preserving native palette tracking and opaque content.
    postPatch =
      (old.postPatch or "")
      + ''
        substituteInPlace core/internal/shellembed/dist/Common/Theme.qml \
          --replace-fail 'readonly property real popupTransparency: 1.0' \
            'readonly property real popupTransparency: ${toString glass.dms.popupTransparency}' \
          --replace-fail 'readonly property real foregroundLayerTransparency: 1.0' \
            'readonly property real foregroundLayerTransparency: ${toString glass.dms.floatingWindowForegroundTransparency}' \
          --replace-fail 'readonly property real floatingWindowTransparency: popupTransparency' \
            'readonly property real floatingWindowTransparency: ${toString glass.dms.floatingWindowTransparency}'

        substituteInPlace \
          core/internal/shellembed/dist/Modules/MainWindow.qml \
          core/internal/shellembed/dist/Modules/ChooserWindow.qml \
          --replace-fail $'    color: Theme.surface\n' $'    color: Theme.floatingWindowSurface\n'
      '';
  })
