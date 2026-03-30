{
  config,
  pkgs,
  inputs,
  lib,
  ...
}: let
  pearpassExtensionId = "pdeffakfmcdnjjafophphgmddmigpejh";
  pearpassNativeHostName = "com.pears.pass";

  pearpassVersion = (builtins.fromJSON (builtins.readFile "${inputs.pearpass-app-desktop}/package.json")).version;

  pearpassSource = pkgs.fetchurl {
    url = "https://github.com/tetherto/pearpass-app-desktop/releases/download/v${pearpassVersion}/PearPass-Desktop-Linux-x64-v${pearpassVersion}.AppImage";
    hash = "sha256-9bYQvh0/+l0RoNsDL9VZiSPHPAgCqOH/qpz5PpE6wb0=";
  };

  # Extract the AppImage to get the icon and resources
  pearpassExtracted = pkgs.appimageTools.extract {
    pname = "pearpass";
    version = pearpassVersion;
    src = pearpassSource;
  };

  # Process the icon to remove the background and resize
  pearpassIcon = pkgs.runCommand "pearpass-icon" {
    buildInputs = [pkgs.imagemagick];
  } ''
    mkdir -p $out
    # Remove background (#232323), trim, and resize to fill standard icon space
    convert ${pearpassExtracted}/PearPass.png \
      -fuzz 20% -transparent "#232323" \
      -trim \
      -resize 600x600 \
      -background none -gravity center -extent 512x512 \
      -unsharp 0x1 \
      $out/PearPass.png
  '';

  # FHS Environment for the GUI (Modern libs)
  pearpassGUIEnv = pkgs.buildFHSEnv (pkgs.appimageTools.defaultFhsEnvArgs // {
    name = "pearpass-gui-env";
    targetPkgs = pkgs:
      with pkgs; (pkgs.appimageTools.defaultFhsEnvArgs.targetPkgs pkgs) ++ [
        gtk4
        graphene
        webkitgtk_6_0
        libsoup_3
        libadwaita
        gnome-themes-extra
        openssl_1_1
        harfbuzz
        icu
        libsecret
        libnotify
      ];
    runScript = "${pearpassExtracted}/AppRun";
  });


  # Helper to write manifests to all browser directories
  writeManifests = pkgs.writeShellScript "pearpass-write-manifests" ''
    for dir in \
      "$HOME/.config/BraveSoftware/Brave-Browser/NativeMessagingHosts" \
      "$HOME/.config/chromium/NativeMessagingHosts" \
      "$HOME/.config/google-chrome/NativeMessagingHosts"; do
      mkdir -p "$dir"
      cp -f ${pearpassManifest} "$dir/${pearpassNativeHostName}.json"
    done
  '';

  # Launcher for the GUI App (Uses Clean Env)
  pearpassLauncher = pkgs.writeShellScriptBin "pearpass-gui" ''
    # Restore our NixOS-compatible native messaging manifests before launch
    ${writeManifests}

    # Launch PearPass (it may overwrite manifests during startup)
    ${pearpassGUIEnv}/bin/pearpass-gui-env "$@"

    # Restore manifests again after PearPass exits
    ${writeManifests}
  '';

  # Wrapper for Native Messaging.
  # Uses pear-runtime directly (it links against Nix glibc fine — no FHS needed).
  # Must cd into PearPass's native-messaging dir so pear-runtime finds its config.
  pearpassNativeWrapper = pkgs.writeShellScript "pearpass-native" ''
    exec 2>/tmp/pearpass-native-error.log

    NATIVE_DIR="$HOME/.config/pear/app-storage/by-dkey"
    # Find the PearPass native-messaging directory (dkey varies per install)
    for d in "$NATIVE_DIR"/*/native-messaging; do
      if [ -d "$d" ]; then
        cd "$d"
        break
      fi
    done

    PEAR_RUNTIME="$HOME/.config/pear/current/by-arch/linux-x64/bin/pear-runtime"
    if [ ! -x "$PEAR_RUNTIME" ]; then
      echo "pear-runtime not found" >&2
      exit 1
    fi

    exec "$PEAR_RUNTIME" run \
      --trusted pear://i49831s3quatekogbc411cdfmg6xmjt1dycxxr3kt1b1qms5x8ro \
      "$@"
  '';

  pearpassManifest = pkgs.writeText "pearpass-manifest.json" (builtins.toJSON {
    name = pearpassNativeHostName;
    description = "PearPass Native Messaging Host";
    path = "${pearpassNativeWrapper}";
    type = "stdio";
    allowed_origins = [
      "chrome-extension://${pearpassExtensionId}/"
    ];
  });
in {
  home.packages = [pearpassLauncher];

  xdg.desktopEntries.pearpass = {
    name = "PearPass";
    exec = "pearpass-gui";
    icon = "${pearpassIcon}/PearPass.png";
    comment = "Password manager with browser integration";
    categories = ["Utility"];
    settings = {
      StartupWMClass = "pear-runtime";
    };
  };

  # Write native messaging manifests as regular files (not symlinks).
  # PearPass GUI overwrites symlinks with its own manifests at startup,
  # which use #!/bin/bash (missing on NixOS). Regular files + the launcher
  # wrapper ensure our FHS-compatible host is always in place.
  home.activation.pearpassNativeManifests = lib.hm.dag.entryAfter ["writeBoundary"] ''
    run ${writeManifests}
  '';
}
