{
  config,
  pkgs,
  ...
}: let
  pearpassExtensionId = "pdeffakfmcdnjjafophphgmddmigpejh";
  pearpassNativeHostName = "com.pears.pass";

  pearpassSource = pkgs.fetchurl {
    url = "https://github.com/tetherto/pearpass-app-desktop/releases/download/v1.3.0/PearPass-Desktop-Linux-x64-v1.3.0.AppImage";
    sha256 = "1fl5g4jb7k6y5j50cm8dfdib2kw31g4c0akz4svkbwf4szwlm1dn";
  };

  pearpassApp = pkgs.appimageTools.wrapType2 {
    pname = "pearpass";
    version = "1.3.0";
    src = pearpassSource;
    extraPkgs = pkgs:
      with pkgs; [
        stdenv.cc.cc.lib
        webkitgtk_6_0
        gtk4
        libadwaita
        pango
        cairo
        gdk-pixbuf
        glib
        graphene
        libsoup_2_4
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
        gnome-themes-extra
        gtk3
        glib-networking
        at-spi2-core
        # Added for tray support / potential missing deps
        libdbusmenu-gtk3
        libappindicator-gtk3
        # Tools
        strace
      ];
  };

  pearpassExtracted = pkgs.appimageTools.extract {
    pname = "pearpass";
    version = "1.3.0";
    src = pearpassSource;
  };

  # Modified wrapper to use strace for debugging silent exits
  pearpassNativeWrapper = pkgs.writeShellScript "pearpass-native" ''
    exec ${pkgs.strace}/bin/strace -f -o /tmp/pearpass-strace.log ${pearpassApp}/bin/pearpass run --trusted pear://rdy3nr56u7k13dppa3sirj4qk3kfz6k7sss6zms3m5rspwr9wery "$@"
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

  xdg.desktopEntries.pearpass = {
    name = "PearPass";
    exec = "pearpass";
    icon = "${pearpassExtracted}/PearPass.png";
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
