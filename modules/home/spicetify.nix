{
  pkgs,
  inputs,
  ...
}: let
  glass = import ./glass.nix;
  spicePkgs = inputs.spicetify-nix.legacyPackages.${pkgs.stdenv.system};
  hazy = glass.spicetify.hazy;
  hazyGlassCss = ''
    :root {
      --backdrop-light: ${hazy.backdropLight} !important;
      --backdrop-lighter: ${hazy.backdropLighter} !important;
      --backdrop: ${hazy.backdrop} !important;
      --backdrop-darker: ${hazy.backdropDarker} !important;
      --backdrop-dark: ${hazy.backdropDark} !important;
      --blur: ${toString hazy.albumArtBlurPx}px !important;
      --cont: ${toString hazy.albumArtContrastPercent}% !important;
      --satu: ${toString hazy.albumArtSaturationPercent}% !important;
      --bright: ${toString hazy.albumArtBrightnessPercent}% !important;
    }

    .encore-layout-themes,
    .encore-dark-theme .encore-announcement-set,
    .encore-bright-accent-set {
      --spice-card: rgba(var(--spice-rgb-card), ${hazy.cardOpacity}) !important;
    }

    .Root__top-container::before {
      opacity: ${hazy.albumArtOpacity} !important;
    }

    .Root__main-view,
    .Root__nav-bar,
    .WBFaUw_oOfN2m4aTxggt,
    .Root__right-sidebar,
    .Root__now-playing-bar,
    .main-view-container,
    .main-topBar-background {
      backdrop-filter: blur(${toString hazy.panelBlurPx}px) !important;
      -webkit-backdrop-filter: blur(${toString hazy.panelBlurPx}px) !important;
    }

    .main-contextMenu-menu,
    .main-contextMenu-tippy > div,
    ul > div[data-tippy-root],
    .Dropdown-menu,
    .marketplace-code-editor,
    .main-trackCreditsModal-mainSection,
    .main-trackCreditsModal-originalCredits,
    .artist-artistAbout-modal,
    .desktopmodals-aboutSpotifyModal-container,
    #recent-searches-dropdown > div,
    #search-dropdown > div,
    #search-suggestions-loading-dropdown > div,
    .CqXpLitKxRFvrULhC2kW.CJCWzxw0S_yJx0wDlvPQ.BGJFigbt4tZ2RFINF8Xu,
    .encore-announcement-set {
      backdrop-filter: blur(${toString hazy.popoverBlurPx}px) !important;
      -webkit-backdrop-filter: blur(${toString hazy.popoverBlurPx}px) !important;
    }

    div#context-menu::before,
    .main-contextMenu-menu::before,
    .Dropdown-menu::before,
    ul > div[data-tippy-root]::before,
    .yzZ_VZHrZBb3REPcU7tD::before {
      content: none !important;
      backdrop-filter: none !important;
      -webkit-backdrop-filter: none !important;
      background: none !important;
      mask-image: none !important;
    }

    .main-contextMenu-menu,
    .main-contextMenu-tippy > div,
    ul > div[data-tippy-root],
    .Dropdown-menu {
      background-color: rgba(var(--spice-rgb-card), ${hazy.cardOpacity}) !important;
      overflow: hidden;
    }

    .main-contextMenu-menuItem > div {
      backdrop-filter: none !important;
      -webkit-backdrop-filter: none !important;
    }

    .search-modal-listbox,
    .search-modal-keyboard-accessibility-bar,
    .VZpSxFV1mVKehHTF1r9W > div {
      background-color: rgba(var(--spice-rgb-card), ${hazy.cardOpacity}) !important;
    }

    div.ZuOMABESRg0Bpv8S9642 > div {
      background-color: rgba(var(--spice-rgb-card), ${hazy.cardOpacity}) !important;
    }
  '';
in {
  programs.spicetify = {
    enable = true;
    theme =
      spicePkgs.themes.hazy
      // {
        additionalCss = hazyGlassCss;
        injectThemeJs = false;
      };
    extraCommands = ''
          for hazyThemeScript in theme.js Extensions/theme.js; do
            if [ ! -f "$hazyThemeScript" ]; then
              continue
            fi

            substituteInPlace "$hazyThemeScript" \
              --replace-fail \
                '(() => {
          const script = document.createElement("SCRIPT");
          script.setAttribute("type", "text/javascript");
          script.setAttribute(
            "src",
            "https://cdn.jsdelivr.net/gh/astromations/hazy/hazy.js"
          );
          document.head.appendChild(script);
        })();' \
                '(() => {
          window.__systemManifestHazyThemeJsPatched = true;
        })();'
          done

          substituteInPlace Extensions/hazy.js \
            --replace-fail \
              '  const defImage = "https://i.imgur.com/Wl2D0h0.png";' \
              '  if (window.__systemManifestHazyLoaded) return;
      window.__systemManifestHazyLoaded = true;

      const systemManifestHazySettingsVersion = "glass-8px-v1";
      if (localStorage.getItem("systemManifestHazySettingsVersion") !== systemManifestHazySettingsVersion) {
        localStorage.setItem("blurAmount", "${toString hazy.albumArtBlurPx}");
        localStorage.setItem("contAmount", "${toString hazy.albumArtContrastPercent}");
        localStorage.setItem("satuAmount", "${toString hazy.albumArtSaturationPercent}");
        localStorage.setItem("brightAmount", "${toString hazy.albumArtBrightnessPercent}");
        localStorage.setItem("systemManifestHazySettingsVersion", systemManifestHazySettingsVersion);
      }

      const defImage = "https://i.imgur.com/Wl2D0h0.png";'

          substituteInPlace Extensions/hazy.js \
            --replace-fail \
              '  // Create edit home topbar button
        const homeEdit = new Spicetify.Topbar.Button("Hazy Settings", "edit", () => {' \
              '  // Create edit home topbar button
        document.querySelectorAll("[aria-label=\"Hazy Settings\"]").forEach((button) => button.remove());
        const homeEdit = new Spicetify.Topbar.Button("Hazy Settings", "edit", () => {'
    '';
  };

  xdg.desktopEntries.spotify = {
    name = "Spotify";
    genericName = "Music Player";
    comment = "Music and podcast streaming client";
    exec = "spotify %U";
    icon = "spotify-client";
    terminal = false;
    categories = ["Audio" "Music" "Player" "AudioVideo"];
    mimeType = ["x-scheme-handler/spotify"];
    settings = {
      StartupWMClass = "spotify";
    };
  };
}
