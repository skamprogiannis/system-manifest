{
  config,
  pkgs,
  ...
}: let
  pearpassExtensionId = "pdeffakfmcdnjjafophphgmddmigpejh";
  pearpassNativeHostName = "com.tetherto.pearpass";

  pearpassApp = pkgs.appimageTools.wrapType2 {
    pname = "pearpass-desktop";
    version = "1.3.0";
    src = pkgs.fetchurl {
      url = "https://github.com/tetherto/pearpass-app-desktop/releases/download/v1.3.0/PearPass-Desktop-Linux-x64-v1.3.0.AppImage";
      sha256 = "1fl5g4jb7k6y5j50cm8dfdib2kw31g4c0akz4svkbwf4szwlm1dn";
    };
    extraPkgs = pkgs:
      with pkgs; [
        webkitgtk_6_0
        gtk4
        libadwaita
        pango
        cairo
        gdk-pixbuf
        glib
        graphene
        libsoup_3
        libsecret
        icu
        libGL
        libglvnd
        vulkan-loader
        libayatana-appindicator
        libnotify
        udev
        alsa-lib
        nss
        nspr
        at-spi2-atk
        libdrm
        mesa
        libxkbcommon
        wayland
        libxshmfence
        libX11
        libXcursor
        libXdamage
        libXext
        libXfixes
        libXi
        libXrender
        libXtst
        libXcomposite
        libXrandr
        libXScrnSaver
        gst_all_1.gstreamer
        gst_all_1.gst-plugins-base
        gst_all_1.gst-plugins-good
        gst_all_1.gst-plugins-bad
        libva
        libvdpau
        # Added for stability
        dbus
        dconf
        xdg-utils
        libz
        openssl
      ];
  };

  pearpassNativeWrapper = pkgs.writeShellScript "pearpass-native" ''
    exec ${pearpassApp}/bin/pearpass-desktop "$@"
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
  home.packages = [pearpassApp];

  home.file = {
    ".local/share/applications/pearpass.desktop".source = "${pearpassApp}/share/applications/pearpass-desktop.desktop";
    ".config/google-chrome/NativeMessagingHosts/${pearpassNativeHostName}.json".source = pearpassManifest;
    ".config/chromium/NativeMessagingHosts/${pearpassNativeHostName}.json".source = pearpassManifest;
    ".config/BraveSoftware/Brave-Browser/NativeMessagingHosts/${pearpassNativeHostName}.json".source = pearpassManifest;
  };
}
