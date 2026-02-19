{
  config,
  pkgs,
  ...
}: let
  pearpassExtensionId = "pdeffakfmcdnjjafophphgmddmigpejh";
  pearpassNativeHostName = "com.pears.pass";

  pearpassSource = pkgs.fetchurl {
    url = "https://github.com/tetherto/pearpass-app-desktop/releases/download/v1.4.0/PearPass-Desktop-Linux-x64-v1.4.0.AppImage";
    sha256 = "19nfy69ygvmqxcgdn46481f8fkhawpl4vlm5888n51rmhd6pic3n";
  };

  # Extract the AppImage to get the icon and resources
  pearpassExtracted = pkgs.appimageTools.extract {
    pname = "pearpass";
    version = "1.4.0";
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

  # FHS Environment for the Native Host (Compatibility libs)
  pearpassNativeEnv = pkgs.buildFHSEnv (pkgs.appimageTools.defaultFhsEnvArgs // {
    name = "pearpass-native-env";
    targetPkgs = pkgs:
      with pkgs; (pkgs.appimageTools.defaultFhsEnvArgs.targetPkgs pkgs) ++ [
        gtk4
        graphene
        webkitgtk_6_0
        libsoup_3
        libsoup_2_4 # REQUIRED
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

  # Launcher for the GUI App (Uses Clean Env)
  pearpassLauncher = pkgs.writeShellScriptBin "pearpass-gui" ''
    exec ${pearpassGUIEnv}/bin/pearpass-gui-env "$@"
  '';

  # Wrapper for Native Messaging (Uses Compat Env)
  # We use the FHS env directly to avoid any wrapper noise on STDOUT
  pearpassNativeWrapper = pkgs.writeShellScript "pearpass-native" ''
    # Redirect ALL output to a debug log except STDIN/STDOUT used for protocol
    exec 2>/tmp/pearpass-native-error.log
    
    # Unset Wayland flags for headless mode
    unset NIXOS_OZONE_WL
    
    # Launch in 'run' mode with trusted URL
    # We call the FHS env binary directly
    exec ${pearpassNativeEnv}/bin/pearpass-native-env run \
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
    comment = "PearPass Password Manager";
    categories = ["Utility"];
    settings = {
      StartupWMClass = "pear-runtime";
    };
  };

  home.file = {
    ".config/google-chrome/NativeMessagingHosts/${pearpassNativeHostName}.json".source = pearpassManifest;
    ".config/chromium/NativeMessagingHosts/${pearpassNativeHostName}.json".source = pearpassManifest;
    ".config/BraveSoftware/Brave-Browser/NativeMessagingHosts/${pearpassNativeHostName}.json".source = pearpassManifest;
  };
}
