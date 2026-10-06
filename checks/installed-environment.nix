{ctx}: let
  inherit (ctx) homeConfig homePackage pkgs spotifyPlayerRemoved;
  installedEnvironment = host: let
    home = homeConfig host;
    profile = home.home.path;
    activation = home.home.activationPackage;
    spotify = home.programs.spicetify.spicedSpotify;
    directlyInstalled = builtins.elem spotify home.home.packages;
  in
    pkgs.runCommand "${host}-installed-environment-checks" {
      nativeBuildInputs = [pkgs.coreutils pkgs.findutils pkgs.gnugrep pkgs.gnused pkgs.shellcheck];
    } ''
      set -euo pipefail
      profile=${profile}
      activation=${activation}
      test ${builtins.toJSON spotifyPlayerRemoved} = true
      test ! -e "$profile/bin/spotify_player"
      ${pkgs.lib.optionalString (host == "desktop") ''
        test ${builtins.toJSON directlyInstalled} = true
        test "$(readlink -f "$profile/bin/spotify")" = "$(readlink -f ${spotify}/bin/spotify)"
        applications="$profile/share/applications"
        test -f "$applications/spotify.desktop"
        test "$(find "$applications" -maxdepth 1 -iname '*spotify*.desktop' | wc -l)" -eq 1
        grep -Fxq 'Exec=spotify %U' "$applications/spotify.desktop"
      ''}
      grep -Fq '/bin/merge-codex-config' "$activation/activate"
      codex_dir_line="$(grep -n 'Activating %s" "ensureWritableCodexDirectory' "$activation/activate" | cut -d: -f1 | head -n1)"
      check_links_line="$(grep -n 'Activating %s" "checkLinkTargets' "$activation/activate" | cut -d: -f1 | head -n1)"
      link_generation_line="$(grep -n 'Activating %s" "linkGeneration' "$activation/activate" | cut -d: -f1 | head -n1)"
      codex_config_line="$(grep -n 'Activating %s" "ensureWritableCodexConfig' "$activation/activate" | cut -d: -f1 | head -n1)"
      test -n "$codex_dir_line" && test -n "$check_links_line"
      test "$codex_dir_line" -lt "$check_links_line"
      test -n "$link_generation_line" && test -n "$codex_config_line"
      test "$codex_config_line" -gt "$link_generation_line"
      codex_seed="$(sed -n 's|.*merge-codex-config \(/nix/store/[^ ]*-codex-config.toml\) .*|\1|p' "$activation/activate" | head -n1)"
      test -n "$codex_seed" && test -f "$codex_seed"
      codex_merger="$(sed -n 's|.*run \(/nix/store/[^ ]*/bin/merge-codex-config\) /nix/store/[^ ]* .*|\1|p' "$activation/activate" | head -n1)"
      test -n "$codex_merger" && test -x "$codex_merger"
      export HOME="$TMPDIR/home"
      mkdir -p "$HOME"
      "$codex_merger" "$codex_seed" "$HOME/.codex/config.toml"
      test -f "$HOME/.codex/config.toml"
      test ! -L "$HOME/.codex/config.toml"
      test "$(stat -c '%a' "$HOME/.codex/config.toml")" = 600
      ${ctx.codexConfigPython}/bin/python3 - "$codex_seed" "$HOME/.codex/config.toml" <<'PY'
      from pathlib import Path
      import sys
      import tomllib

      seed, merged = [tomllib.loads(Path(path).read_text()) for path in sys.argv[1:]]
      assert merged["model"] == seed["model"]
      assert merged["mcp_servers"] == seed["mcp_servers"]
      PY
      assert_file_contains() {
        if ! grep -Fq -- "$2" "$1"; then
          echo "Expected $1 to contain: $2" >&2
          exit 1
        fi
      }
      ${pkgs.lib.optionalString (host == "desktop") ''
        test "$(readlink -f "$profile/bin/brave")" = "$(readlink -f ${ctx.desktopBravePackage}/bin/brave)"
        test "$(readlink -f "$profile/bin/nvim")" = "$(readlink -f ${ctx.desktopNeovimPackage}/bin/nvim)"
        assert_file_contains "$profile/share/applications/com.brave.Browser.desktop" 'Exec=brave %U'
        assert_file_contains "$profile/share/applications/transmission.desktop" 'Exec=torrent gui'
        assert_file_contains "$profile/share/applications/torrent-add.desktop" 'Exec=torrent add %U'
          ${pkgs.lib.optionalString ctx.desktopBannerlordEnabled ''
          shellcheck -S warning \
            ${homePackage "desktop" "bannerlord-speech-runtime"}/bin/bannerlord-speech \
            ${homePackage "desktop" "bannerlord-speech-runtime"}/bin/bannerlord-speech-service
        ''}
      ''}
      ${pkgs.lib.optionalString (host == "usb") ''
          usb_steam_launcher=${ctx.usbSteamLauncher}
          usb_host_auto_steam_launcher=${ctx.usbHostAutoSteamLauncher}
          usb_steam_host_scratch_prepare=${ctx.usbSteamHostScratchPrepareScript}
          assert_file_contains() {
            if ! grep -Fq -- "$2" "$1"; then echo "$3" >&2; exit 1; fi
          }
          assert_not_file_contains() {
            if grep -Fq -- "$2" "$1"; then echo "$3" >&2; exit 1; fi
          }
        assert_not_file_contains "$usb_steam_launcher" \
          "/nix/.host-scratch/user/stefan/steam/Steam" \
          "Expected normal USB Steam to keep its persistent data-home behavior."
        assert_file_contains "$usb_host_auto_steam_launcher" \
          "$usb_steam_host_scratch_prepare" \
          "Expected host-auto Steam to invoke its host-scratch preparation script."

      ''}
      touch "$out"
    '';
in {
  desktop-installed-environment = installedEnvironment "desktop";
  usb-installed-environment = installedEnvironment "usb";
}
