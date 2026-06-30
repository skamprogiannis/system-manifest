{
  config,
  pkgs,
  lib,
  ...
}: let
  pearpassExtensionId = "pdeffakfmcdnjjafophphgmddmigpejh";
  pearpassNativeHostName = "com.pears.pass";
  pearpassStateDir = "${config.xdg.stateHome}/pearpass";
  pearpassNativeErrorLog = "${pearpassStateDir}/native-error.log";
  pearpassChromiumArgs = [
    "--ozone-platform-hint=auto"
    "--enable-wayland-ime=true"
  ];

  # Upstream's source repo version can move ahead of the published Linux
  # AppImage release. Keep following the repo for manifests/runtime data, but
  # fetch the latest Linux asset that is actually published.
  pearpassReleaseVersion = "2.1.0";

  pearpassAppImageSource = pkgs.fetchurl {
    url = "https://github.com/tetherto/pearpass-app-desktop/releases/download/v${pearpassReleaseVersion}/PearPass-Desktop-Linux-x64-v${pearpassReleaseVersion}.AppImage";
    hash = "sha256-3iqUrulYMRLSSgNkLZqLamVIcI51iriWZVw7Y4VLxe8=";
  };

  pearpassSource = pearpassAppImageSource;

  # Extract the AppImage to get the icon and resources
  pearpassExtracted = pkgs.appimageTools.extract {
    pname = "pearpass";
    version = pearpassReleaseVersion;
    src = pearpassSource;
  };
  pearpassAppBinary = "${pearpassExtracted}/pearpass-app-desktop.bin";
  pearpassNativeBridge = "${pearpassExtracted}/resources/app/dist/native-messaging-bridge.bundle.cjs";

  # Process the icon to remove the background and resize
  pearpassIcon =
    pkgs.runCommand "pearpass-icon" {
      buildInputs = [pkgs.imagemagick];
    } ''
      mkdir -p $out
      # Remove background (#232323), trim, and resize to fill standard icon space
      convert ${pearpassExtracted}/usr/share/icons/hicolor/1024x1024/apps/pearpass-app-desktop.png \
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

  pearpassFHSTargetPkgs = pkgs:
    with pkgs;
      (pkgs.appimageTools.defaultFhsEnvArgs.targetPkgs pkgs)
      ++ [
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

  pearpassGUIEnv = pkgs.buildFHSEnv (pkgs.appimageTools.defaultFhsEnvArgs
    // {
      name = "pearpass-gui-env";
      targetPkgs = pearpassFHSTargetPkgs;
      runScript = "${pearpassExtracted}/AppRun";
    });

  pearpassNativeEnv = pkgs.buildFHSEnv (pkgs.appimageTools.defaultFhsEnvArgs
    // {
      name = "pearpass-native-env";
      targetPkgs = pearpassFHSTargetPkgs;
      runScript = pearpassAppBinary;
    });

  # Helper to write manifests to all browser directories.
  writeManifests = pkgs.writeShellScript "pearpass-write-manifests" ''
    set -euo pipefail

    for dir in \
      "$HOME/.config/BraveSoftware/Brave-Browser/NativeMessagingHosts" \
      "$HOME/.config/chromium/NativeMessagingHosts" \
      "$HOME/.config/google-chrome/NativeMessagingHosts"; do
      ${pkgs.coreutils}/bin/mkdir -p "$dir"

      target="$dir/${pearpassNativeHostName}.json"
      if [ -f "$target" ] && ${pkgs.diffutils}/bin/cmp -s ${pearpassManifest} "$target"; then
        continue
      fi

      tmp=$(${pkgs.coreutils}/bin/mktemp "$dir/.${pearpassNativeHostName}.json.XXXXXX")
      ${pkgs.coreutils}/bin/cp -f ${pearpassManifest} "$tmp"
      ${pkgs.coreutils}/bin/chmod 0644 "$tmp"
      ${pkgs.coreutils}/bin/mv -f "$tmp" "$target"
    done
  '';

  # Launcher for the GUI App (Uses Clean Env)
  pearpassLauncher = pkgs.writeShellScriptBin "pearpass-gui" ''
    # PearPass rewrites browser manifests, so restore the Nix-managed ones before launch.
    ${writeManifests}

    export ELECTRON_OZONE_PLATFORM_HINT=auto

    # PearPass may overwrite the manifests again while it runs.
    ${pearpassGUIEnv}/bin/pearpass-gui-env ${lib.escapeShellArgs pearpassChromiumArgs} "$@"

    # Restore the Nix-managed manifests after exit as well.
    ${writeManifests}
  '';

  # Wrapper for native messaging. Upstream launches this bridge with the
  # Electron binary in Node mode, so it needs the same FHS libraries as the GUI.
  pearpassNativeWrapper = pkgs.writeShellScript "pearpass-native" ''
    mkdir -p ${lib.escapeShellArg pearpassStateDir}
    exec 2>${lib.escapeShellArg pearpassNativeErrorLog}

    export ELECTRON_RUN_AS_NODE=1
    exec ${pearpassNativeEnv}/bin/pearpass-native-env \
      ${lib.escapeShellArg pearpassNativeBridge} \
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
  # PearPass GUI overwrites manifests with upstream hosts that use /bin/bash or
  # an unwrapped Electron binary. Keep restoring the Nix-wrapped bridge.
  home.activation.pearpassNativeManifests = lib.hm.dag.entryAfter ["writeBoundary"] ''
    run ${writeManifests}
  '';

  systemd.user.services.pearpass-native-manifests = {
    Unit = {
      Description = "Restore PearPass browser native messaging manifests";
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${writeManifests}";
    };
  };

  systemd.user.paths.pearpass-native-manifests = {
    Unit = {
      Description = "Watch PearPass browser native messaging manifests";
    };
    Path = {
      PathChanged = [
        "%h/.config/BraveSoftware/Brave-Browser/NativeMessagingHosts"
        "%h/.config/chromium/NativeMessagingHosts"
        "%h/.config/google-chrome/NativeMessagingHosts"
      ];
      Unit = "pearpass-native-manifests.service";
    };
    Install = {
      WantedBy = ["default.target"];
    };
  };
}
