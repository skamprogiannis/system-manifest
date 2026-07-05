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
      --system-spicetify-quick-search-surface: rgba(var(--spice-rgb-card), ${hazy.quickSearchSurfaceOpacity}) !important;
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
    .Dropdown-menu,
    [data-tippy-root]:has([role="menu"]) [role="menu"],
    .marketplace-code-editor,
    .main-trackCreditsModal-mainSection,
    .main-trackCreditsModal-originalCredits,
    .artist-artistAbout-modal,
    .desktopmodals-aboutSpotifyModal-container,
    #recent-searches-dropdown > div,
    #search-dropdown > div,
    #search-suggestions-loading-dropdown > div,
    [role="dialog"]:has(input[placeholder="What do you want to play?"]),
    [role="dialog"]:has(.search-modal-listbox),
    .encore-announcement-set {
      backdrop-filter: blur(${toString hazy.popoverBlurPx}px) !important;
      -webkit-backdrop-filter: blur(${toString hazy.popoverBlurPx}px) !important;
    }

    div#context-menu::before,
    .main-contextMenu-menu::before,
    .Dropdown-menu::before,
    [data-tippy-root]:has([role="menu"])::before,
    .yzZ_VZHrZBb3REPcU7tD::before {
      content: none !important;
      backdrop-filter: none !important;
      -webkit-backdrop-filter: none !important;
      background: none !important;
      mask-image: none !important;
      pointer-events: none !important;
    }

    .main-contextMenu-tippy,
    .main-contextMenu-tippy > div,
    [data-tippy-root]:has([role="menu"]) {
      background: transparent !important;
      backdrop-filter: none !important;
      -webkit-backdrop-filter: none !important;
      overflow: visible !important;
    }

    .main-contextMenu-menu,
    .Dropdown-menu,
    [data-tippy-root]:has([role="menu"]) [role="menu"] {
      background-color: rgba(var(--spice-rgb-card), ${hazy.cardOpacity}) !important;
      overflow: visible !important;
    }

    .main-contextMenu-menuItem > div,
    .main-contextMenu-menuItemButton {
      backdrop-filter: none !important;
      -webkit-backdrop-filter: none !important;
    }

    [data-tippy-root]:has([role="menu"]) [role="menu"] button,
    .main-contextMenu-menu button,
    .Dropdown-menu button {
      pointer-events: auto !important;
    }

    [data-system-manifest-row-play-tooltip="true"] {
      visibility: hidden !important;
      opacity: 0 !important;
      pointer-events: none !important;
    }

    [role="dialog"]:has(input[placeholder="What do you want to play?"]),
    [role="dialog"]:has(.search-modal-listbox),
    .search-modal-listbox,
    .search-modal-keyboard-accessibility-bar {
      background-color: var(--system-spicetify-quick-search-surface) !important;
    }

    [role="dialog"]:has(input[placeholder="What do you want to play?"]) form,
    [role="dialog"]:has(input[placeholder="What do you want to play?"]) form div:has(> input[placeholder="What do you want to play?"]),
    [role="dialog"]:has(.search-modal-listbox) input,
    [role="dialog"]:has(input[placeholder="What do you want to play?"]) input {
      background: transparent !important;
      border: 0 !important;
      outline: none !important;
      box-shadow: none !important;
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

      const markSystemManifestRowPlayTooltips = () => {
        const markTooltip = (root) => {
          const tooltip = root.querySelector("[role=\"tooltip\"]");
          if (!tooltip) return;

          const label = (tooltip.textContent || "").trim();
          if (!/^Play\s+.+\s+by\s+.+$/.test(label)) return;

          root.dataset.systemManifestRowPlayTooltip = "true";
          root.setAttribute("aria-hidden", "true");
        };

        document.querySelectorAll("[data-tippy-root]").forEach(markTooltip);

        const observer = new MutationObserver((mutations) => {
          for (const mutation of mutations) {
            for (const node of mutation.addedNodes) {
              if (!(node instanceof Element)) continue;
              if (node.matches("[data-tippy-root]")) markTooltip(node);
              node.querySelectorAll("[data-tippy-root]").forEach(markTooltip);
            }
          }
        });

        if (document.body) {
          observer.observe(document.body, { childList: true, subtree: true });
        }
      };

      markSystemManifestRowPlayTooltips();

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
