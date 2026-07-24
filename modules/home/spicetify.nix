{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: let
  glass = import ./glass.nix;
  spotifyPkgs = import inputs.spotify-nixpkgs {
    system = pkgs.stdenv.hostPlatform.system;
    config.allowUnfree = true;
  };
  spicePkgs = inputs.spicetify-nix.legacyPackages.${pkgs.stdenv.system};
  spotifyHybridPackage = pkgs.spotify.overrideAttrs (_: {
    inherit (spotifyPkgs.spotify) version rev src;
  });
  spotifyRenderPolicyVersion = "spotify-gpu-fallback-v1";
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
  spotifyLauncher = pkgs.writeShellApplication {
    name = "spotify";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.libnotify
      pkgs.util-linux
    ];
    text = ''
      real_spotify="${config.programs.spicetify.spicedSpotify}/bin/spotify"
      package_id="${config.programs.spicetify.spicedSpotify}"
      policy_version="${spotifyRenderPolicyVersion}"
      fingerprint_file="/run/system-manifest/host-fingerprint"
      notify_bin="${pkgs.libnotify}/bin/notify-send"
      healthy_seconds=30

      if [ "''${SYSTEM_MANIFEST_SPOTIFY_TEST_MODE:-}" = "1" ]; then
        real_spotify="''${SYSTEM_MANIFEST_SPOTIFY_REAL_BIN:?test mode requires SYSTEM_MANIFEST_SPOTIFY_REAL_BIN}"
        fingerprint_file="''${SYSTEM_MANIFEST_SPOTIFY_FINGERPRINT_FILE:-$fingerprint_file}"
        notify_bin="''${SYSTEM_MANIFEST_SPOTIFY_NOTIFY_BIN:-$notify_bin}"
        healthy_seconds="''${SYSTEM_MANIFEST_SPOTIFY_HEALTHY_SECONDS:-$healthy_seconds}"
      fi

      state_home="''${XDG_STATE_HOME:-''${HOME:?HOME is required}/.local/state}"
      state_dir="$state_home/system-manifest/render-compat"
      mkdir -p "$state_dir"
      chmod 0700 "$state_dir"

      if [ -r "$fingerprint_file" ]; then
        host_identity="$(head -n 1 "$fingerprint_file")"
      elif [ -r /etc/machine-id ]; then
        host_identity="$(head -n 1 /etc/machine-id)"
      else
        host_identity="local"
      fi
      host_key="$(printf '%s' "$host_identity" | sha256sum | cut -d ' ' -f 1)"
      cache_file="$state_dir/spotify-$host_key.conf"
      last_stderr="$state_dir/spotify-last-stderr.log"

      invocation_dir="$(mktemp -d "''${XDG_RUNTIME_DIR:-''${TMPDIR:-/tmp}}/spotify-launcher.XXXXXX")"
      invocation_log="$invocation_dir/stderr.log"
      : > "$invocation_log"
      child_pid=""
      signaled_child_pid=""
      forwarded_signal=""
      forwarded_status=""
      spawning_child=0

      # ShellCheck does not follow functions invoked only through traps.
      # shellcheck disable=SC2329
      cleanup() {
        cp "$invocation_log" "$last_stderr" 2>/dev/null || true
        chmod 0600 "$last_stderr" 2>/dev/null || true
        rm -rf "$invocation_dir"
      }

      signal_child() {
        local signal="$1"
        if [ -n "$child_pid" ] && kill -0 "$child_pid" 2>/dev/null; then
          signaled_child_pid="$child_pid"
          kill -s "$signal" -- "-$child_pid" 2>/dev/null || kill -s "$signal" "$child_pid" 2>/dev/null || true
          sleep 2
          if kill -0 "$child_pid" 2>/dev/null; then
            kill -KILL -- "-$child_pid" 2>/dev/null || kill -KILL "$child_pid" 2>/dev/null || true
          fi
          return 0
        fi
        return 1
      }

      # shellcheck disable=SC2329
      forward_signal() {
        forwarded_signal="$1"
        forwarded_status="$2"
        if signal_child "$forwarded_signal"; then
          return
        fi
        if [ "$spawning_child" -eq 0 ]; then
          exit "$forwarded_status"
        fi
      }

      trap cleanup EXIT
      trap 'forward_signal INT 130' INT
      trap 'forward_signal TERM 143' TERM
      trap 'forward_signal QUIT 131' QUIT

      run_spotify() {
        local mode="$1"
        shift
        local attempt_log="$invocation_dir/$mode.stderr.log"
        local health_probe_lock="$invocation_dir/$mode.health.lock"
        local health_probe_sentinel="$invocation_dir/$mode.health.pending"
        local status

        if [ -n "$forwarded_status" ]; then
          return "$forwarded_status"
        fi

        : > "$attempt_log"
        spawning_child=1
        env \
          --default-signal=INT \
          --default-signal=TERM \
          --default-signal=QUIT \
          setsid --wait "$real_spotify" "$@" 2>"$attempt_log" &
        child_pid="$!"
        spawning_child=0

        if [ "$mode" = "software-fallback" ]; then
          touch "$health_probe_sentinel"
          (
            sleep "$healthy_seconds"
            if ! { exec 9>"$health_probe_lock"; } 2>/dev/null; then
              exit 0
            fi
            flock 9 || exit 0
            if [ -e "$health_probe_sentinel" ] && kill -0 "$child_pid" 2>/dev/null; then
              write_software_cache || true
            fi
          ) &
        fi

        if [ -n "$forwarded_signal" ] && [ "$signaled_child_pid" != "$child_pid" ]; then
          signal_child "$forwarded_signal"
        fi

        while true; do
          if wait "$child_pid"; then
            status=0
          else
            status="$?"
          fi
          if ! kill -0 "$child_pid" 2>/dev/null; then
            break
          fi
        done
        child_pid=""
        if [ "$mode" = "software-fallback" ]; then
          exec 8>"$health_probe_lock"
          flock 8
          rm -f "$health_probe_sentinel"
          flock -u 8
          exec 8>&-
        fi

        {
          printf '== %s ==\n' "$mode"
          cat "$attempt_log"
        } >> "$invocation_log"
        cat "$attempt_log" >&2

        if [ -n "$forwarded_status" ]; then
          return "$forwarded_status"
        fi
        return "$status"
      }

      cache_uses_software() {
        [ -f "$cache_file" ] \
          && grep -Fxq "policy=$policy_version" "$cache_file" \
          && grep -Fxq "package=$package_id" "$cache_file" \
          && grep -Fxq "mode=software" "$cache_file"
      }

      write_software_cache() {
        local cache_tmp
        cache_tmp="$(mktemp "$cache_file.tmp.XXXXXX")"
        {
          printf 'policy=%s\n' "$policy_version"
          printf 'package=%s\n' "$package_id"
          printf 'mode=software\n'
        } > "$cache_tmp"
        chmod 0600 "$cache_tmp"
        mv -f "$cache_tmp" "$cache_file"
      }

      notify_packaging_failure() {
        echo "spotify: Mesa/glibc runtime mismatch; automatic GPU fallback is unsafe" >&2
        "$notify_bin" \
          --app-name=Spotify \
          "Spotify packaging error" \
          "Mesa and glibc are incompatible. GPU fallback was not attempted." \
          >/dev/null 2>&1 || true
      }

      has_disable_gpu=false
      for argument in "$@"; do
        if [ "$argument" = "--disable-gpu" ]; then
          has_disable_gpu=true
          break
        fi
      done

      if cache_uses_software && [ "$has_disable_gpu" = false ]; then
        if run_spotify software-cached --disable-gpu "$@"; then
          status=0
        else
          status="$?"
        fi
        if [ "$status" -ne 0 ] && [ -z "$forwarded_status" ]; then
          rm -f "$cache_file"
        fi
        exit "$status"
      fi

      if run_spotify normal "$@"; then
        status=0
      else
        status="$?"
      fi
      if [ "$status" -eq 0 ] || [ -n "$forwarded_status" ]; then
        exit "$status"
      fi

      normal_log="$invocation_dir/normal.stderr.log"
      if grep -Fq "MESA-LOADER" "$normal_log" \
        && grep -Eq "GLIBC[^[:space:]]*.*not found" "$normal_log"; then
        notify_packaging_failure
        exit "$status"
      fi

      if [ "$has_disable_gpu" = false ] \
        && grep -Fq "GPU process isn't usable" "$normal_log"; then
        if run_spotify software-fallback --disable-gpu "$@"; then
          fallback_status=0
        else
          fallback_status="$?"
        fi
        if [ "$fallback_status" -eq 0 ]; then
          write_software_cache
        elif [ -z "$forwarded_status" ]; then
          rm -f "$cache_file"
        fi
        exit "$fallback_status"
      fi

      exit "$status"
    '';
  };
in {
  programs.spicetify = {
    enable = true;
    spotifyPackage = spotifyHybridPackage;
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

  home.packages = [
    ((lib.hiPrio spotifyLauncher).overrideAttrs (_: {
      passthru.systemManifestSpotifyLauncher = true;
    }))
  ];

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
