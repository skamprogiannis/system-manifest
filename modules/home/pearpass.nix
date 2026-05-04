{
  config,
  pkgs,
  inputs,
  lib,
  ...
}: let
  pearpassExtensionId = "pdeffakfmcdnjjafophphgmddmigpejh";
  pearpassNativeHostName = "com.pears.pass";
  pearpassStateDir = "${config.xdg.stateHome}/pearpass";
  pearpassNativeErrorLog = "${pearpassStateDir}/native-error.log";
  pearpassPackageJson = builtins.fromJSON (builtins.readFile "${inputs.pearpass-app-desktop}/package.json");
  pearpassVersion =
    let
      version =
        pearpassPackageJson.version
        or (throw "pearpass-app-desktop/package.json is missing the version field");
    in
      if builtins.isString version
      then version
      else throw "pearpass-app-desktop/package.json version must be a string";

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
  # Keep OpenSSL 1.1 for AppImage compatibility, but disable its upstream test
  # suite to avoid sporadic CI failures in legacy ssl session ticket tests.
  pearpassOpenSSL11 = pkgs.openssl_1_1.overrideAttrs (_: {
    doCheck = false;
  });

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
        pearpassOpenSSL11
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
    # PearPass rewrites browser manifests, so restore the Nix-managed ones before launch.
    ${writeManifests}

    # PearPass may overwrite the manifests again while it runs.
    ${pearpassGUIEnv}/bin/pearpass-gui-env "$@"

    # Restore the Nix-managed manifests after exit as well.
    ${writeManifests}
  '';

  # Wrapper for Native Messaging.
  # Uses pear-runtime directly (it links against Nix glibc fine — no FHS needed).
  # Must cd into PearPass's native-messaging dir so pear-runtime finds its config.
  pearpassNativeWrapper = pkgs.writeShellScript "pearpass-native" ''
    mkdir -p ${lib.escapeShellArg pearpassStateDir}
    exec 2>${lib.escapeShellArg pearpassNativeErrorLog}

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
