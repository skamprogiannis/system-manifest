{
  config,
  pkgs,
  lib,
  hostType ? "desktop",
  ...
}:
assert lib.assertMsg (builtins.elem hostType ["desktop" "usb" "laptop"]) "hostType must be \"desktop\", \"usb\", or \"laptop\"."; let
  spotifyDeviceName =
    if hostType == "usb"
    then "nixos-usb"
    else if hostType == "laptop"
    then "nixos-laptop"
    else "nixos-desktop";
  spotifyServiceName = "spotify-player.service";
  spotifySharedClientId = "65b708073fc0480ea92a077233ca87bd";
  spotifyPlayerClientPatch = pkgs.writeText "patch-spotify-player-client.py" (lib.strings.removePrefix "    " (builtins.replaceStrings ["\n    "] ["\n"] ''
    import re
    from pathlib import Path

    client_path = Path("spotify_player/src/client/mod.rs")
    client_text = client_path.read_text()
    auth_path = Path("spotify_player/src/auth.rs")
    auth_text = auth_path.read_text()

    new_popup = """        #[cfg(feature = "streaming")]
        {
            if state.is_streaming_enabled() {
                let configs = config::get_config();
                let session = self.spotify.session().await;
                let local_device = Device {
                    id: session.device_id().to_string(),
                    name: configs.app_config.device.name.clone(),
                };

                // Only add if not already in the list (avoid duplicates)
                if !devices.iter().any(|d| d.id == local_device.id) {
                    devices.push(local_device);
                }
            }
        }
    """

    new_default = """        #[cfg(feature = "streaming")]
        {
            if configs.app_config.enable_streaming == config::StreamingType::Always {
                let session = self.spotify.session().await;
                devices.push((
                    configs.app_config.device.name.clone(),
                    session.device_id().to_string(),
                ));
            }
        }
    """

    popup_pattern = re.compile(
        r"""^[ \t]+#\[cfg\(feature = "streaming"\)\]\n"""
        r"""[ \t]+\{\n"""
        r"""[ \t]+let configs = config::get_config\(\);\n"""
        r"""[ \t]+let session = self\.spotify\.session\(\)\.await;\n"""
        r"""[ \t]+let local_device = Device \{\n"""
        r"""[ \t]+id: session\.device_id\(\)\.to_string\(\),\n"""
        r"""[ \t]+name: configs\.app_config\.device\.name\.clone\(\),\n"""
        r"""[ \t]+\};\n\n"""
        r"""[ \t]+// Only add if not already in the list \(avoid duplicates\)\n"""
        r"""[ \t]+if !devices\.iter\(\)\.any\(\|d\| d\.id == local_device\.id\) \{\n"""
        r"""[ \t]+devices\.push\(local_device\);\n"""
        r"""[ \t]+\}\n"""
        r"""[ \t]+\}\n""",
        re.MULTILINE,
    )
    default_pattern = re.compile(
        r"""^[ \t]+#\[cfg\(feature = "streaming"\)\]\n"""
        r"""[ \t]+\{\n"""
        r"""[ \t]+let session = self\.spotify\.session\(\)\.await;\n"""
        r"""[ \t]+devices\.push\(\(\n"""
        r"""[ \t]+configs\.app_config\.device\.name\.clone\(\),\n"""
        r"""[ \t]+session\.device_id\(\)\.to_string\(\),\n"""
        r"""[ \t]+\)\);\n"""
        r"""[ \t]+\}\n""",
        re.MULTILINE,
    )

    auth_config_struct_pattern = re.compile(
        r"""(?ms)^#\[derive\(Clone\)\]\n"""
        r"""pub struct AuthConfig \{\n"""
        r"""    pub cache: Cache,\n"""
        r"""    pub session_config: SessionConfig,\n"""
        r"""    pub login_redirect_uri: String,\n"""
        r"""\}\n"""
    )
    auth_config_struct_new = """#[derive(Clone)]
pub struct AuthConfig {
    pub cache: Cache,
    pub session_config: SessionConfig,
    pub client_id: String,
    pub login_redirect_uri: String,
}
"""
    auth_default_pattern = re.compile(
        r"""(?ms)^        AuthConfig \{\n"""
        r"""            cache: Cache::new\(None::<String>, None, None, None\)\.unwrap\(\),\n"""
        r"""            session_config: SessionConfig::default\(\),\n"""
        r"""            login_redirect_uri: "http://127\.0\.0\.1:8989/login"\.to_string\(\),\n"""
        r"""        \}\n"""
    )
    auth_default_new = """        AuthConfig {
            cache: Cache::new(None::<String>, None, None, None).unwrap(),
            session_config: SessionConfig::default(),
            client_id: SPOTIFY_CLIENT_ID.to_string(),
            login_redirect_uri: "http://127.0.0.1:8989/login".to_string(),
        }
"""
    auth_new_pattern = re.compile(
        r"""(?ms)^        Ok\(AuthConfig \{\n"""
        r"""            cache,\n"""
        r"""            session_config: configs\.app_config\.session_config\(\),\n"""
        r"""            login_redirect_uri: configs\.app_config\.login_redirect_uri\.clone\(\),\n"""
        r"""        \}\)\n"""
    )
    auth_new_new = """        let client_id = configs
            .app_config
            .get_user_client_id()?
            .unwrap_or_else(|| SPOTIFY_CLIENT_ID.to_string());

        Ok(AuthConfig {
            cache,
            session_config: configs.app_config.session_config(),
            client_id,
            login_redirect_uri: configs.app_config.login_redirect_uri.clone(),
        })
"""
    auth_oauth_pattern = re.compile(
        r"""(?ms)^                let client_builder = OAuthClientBuilder::new\(\n"""
        r"""                    SPOTIFY_CLIENT_ID,\n"""
        r"""                    &auth_config\.login_redirect_uri,\n"""
        r"""                    OAUTH_SCOPES\.to_vec\(\),\n"""
        r"""                \)\n"""
    )
    auth_oauth_new = """                let oauth_scopes = if auth_config.client_id == SPOTIFY_CLIENT_ID {
                    OAUTH_SCOPES.to_vec()
                } else {
                    OAUTH_SCOPES
                        .iter()
                        .copied()
                        .filter(|scope| *scope != "user-personalized")
                        .collect()
                };
                let client_builder = OAuthClientBuilder::new(
                    &auth_config.client_id,
                    &auth_config.login_redirect_uri,
                    oauth_scopes,
                )
"""

    client_text, popup_count = popup_pattern.subn(new_popup, client_text, count=1)
    if popup_count != 1:
        raise SystemExit("spotify-player popup device block not found")
    client_text, default_count = default_pattern.subn(new_default, client_text, count=1)
    if default_count != 1:
        raise SystemExit("spotify-player default device block not found")
    client_path.write_text(client_text)

    auth_text, auth_struct_count = auth_config_struct_pattern.subn(auth_config_struct_new, auth_text, count=1)
    if auth_struct_count != 1:
        raise SystemExit("spotify-player auth config struct block not found")

    auth_text, auth_default_count = auth_default_pattern.subn(auth_default_new, auth_text, count=1)
    if auth_default_count != 1:
        raise SystemExit("spotify-player auth default block not found")

    auth_text, auth_new_count = auth_new_pattern.subn(auth_new_new, auth_text, count=1)
    if auth_new_count != 1:
        raise SystemExit("spotify-player auth config constructor block not found")

    auth_text, auth_oauth_count = auth_oauth_pattern.subn(auth_oauth_new, auth_text, count=1)
    if auth_oauth_count != 1:
        raise SystemExit("spotify-player auth OAuth block not found")

    auth_path.write_text(auth_text)

    # Patch rspotify-model to handle Spotify API field removals.
    # Spotify silently dropped these fields from their responses; rspotify
    # still requires them → every user library call fails deserialization.
    import os as _os
    _vendor = _os.environ.get("cargoDepsCopy", "")
    if not _vendor:
        print("WARNING: cargoDepsCopy not set, skipping rspotify-model patches")
    else:
        _rsp_candidates = []
        for _root, _dirs, _files in _os.walk(_vendor):
            if _os.path.basename(_root) == "rspotify-model-0.15.3":
                _candidate = _os.path.join(_root, "src")
                if _os.path.isdir(_candidate):
                    _rsp_candidates.append(_candidate)
        if len(_rsp_candidates) != 1:
            raise SystemExit(f"expected one rspotify-model source tree, found {len(_rsp_candidates)}")
        _rsp_src = _rsp_candidates[0]
        def _serde_default(text, field):
            return text.replace("    " + field, "    #[serde(default)]\n    " + field)
        _rsp_patches = [
            ("artist.rs", ["pub genres: Vec<String>,", "pub followers: Followers,", "pub popularity: u32,"]),
            ("album.rs", ["pub popularity: u32,"]),
            ("track.rs", ["pub popularity: u32,", "pub external_ids: HashMap<String, String>,"]),
            ("playlist.rs", ["pub tracks: PlaylistTracksRef,", "pub tracks: Page<PlaylistItem>,"]),
            ("show.rs", ["pub available_markets: Vec<String>,", "pub publisher: String,"]),
        ]
        for _fn, _fields in _rsp_patches:
            _fpath = _os.path.join(_rsp_src, _fn)
            if not _os.path.exists(_fpath):
                print(f"WARNING: {_fpath} not found, skipping")
                continue
            _text = open(_fpath).read()
            for _fld in _fields:
                _text = _serde_default(_text, _fld)
            open(_fpath, "w").write(_text)
            print(f"Patched rspotify-model: {_fn}")
  ''));
  spotifyPlayerUpstreamPkg = pkgs.spotify-player;
  spotifyPlayerRawPkg = spotifyPlayerUpstreamPkg.overrideAttrs (old: {
    postPatch =
      (old.postPatch or "")
      + ''
        ${pkgs.python3}/bin/python3 ${spotifyPlayerClientPatch}
      '';
  });
  spotifyConfigDir = "${config.xdg.configHome}/spotify-player";
  spotifyCacheDir = "${config.xdg.cacheHome}/spotify-player";
  spotifyDaemonConfigDir = "${config.xdg.configHome}/spotify-player-daemon";
  spotifyDaemonArgs = "-c ${spotifyDaemonConfigDir} --daemon";
  spotifyClientIdFile = "${spotifyConfigDir}/client_id";
  spotifyClientIdStamp = "${config.xdg.stateHome}/system-manifest/spotify-client-id-v1";
  spotifyClientIdCommand = pkgs.writeShellScript "spotify-player-client-id" ''
    set -euo pipefail

    client_id_file="${spotifyClientIdFile}"
    if [ -s "$client_id_file" ]; then
      exec ${pkgs.coreutils}/bin/cat "$client_id_file"
    fi

    printf '%s\n' "${spotifySharedClientId}"
  '';

  # Subcommands that need the daemon running. Everything else (and any
  # unknown command/flag) is passed straight through to the real binary.
  appTomlCommon = ''
    client_port = 8081
    login_redirect_uri = "http://127.0.0.1:8989/login"
    client_id_command = { command = "${spotifyClientIdCommand}", args = [] }
    app_refresh_duration_in_ms = 32
    default_device = "${spotifyDeviceName}"

    [device]
    name = "${spotifyDeviceName}"
    device_type = "computer"
    volume = 80
    bitrate = 320
    audio_cache = true
    normalization = false
  '';

  spotifyPlayerPkg = pkgs.writeShellScriptBin "spotify_player" ''
    set -euo pipefail

    real_player="${spotifyPlayerRawPkg}/bin/spotify_player"
    service="${spotifyServiceName}"
    cache_dir="${spotifyCacheDir}"
    client_id_file="${spotifyClientIdFile}"
    client_id_stamp="${spotifyClientIdStamp}"
    creds="${spotifyCacheDir}/credentials.json"
    web_token="${spotifyCacheDir}/user_client_token.json"
    auth_attempted=0
    shopt -s nullglob

    effective_client_id() {
      "${spotifyClientIdCommand}"
    }

    sync_client_id_cache() {
      local current_id previous_id
      current_id="$(effective_client_id)"
      mkdir -p "$(${pkgs.coreutils}/bin/dirname "$client_id_stamp")"

      if [ -s "$client_id_stamp" ]; then
        previous_id="$(<"$client_id_stamp")"
        if [ "$previous_id" != "$current_id" ]; then
          rm -f "$creds" "$web_token"
          echo "spotify_player: Spotify client ID changed; clearing cached auth before re-authenticating" >&2
        fi
      fi

      printf '%s\n' "$current_id" > "$client_id_stamp"
    }

    needs_daemon() {
      [ "$#" -eq 0 ] && return 0
      case "$1" in
        playback|connect|like|get) return 0 ;;
      esac
      return 1
    }

    service_has_failed() {
      ${pkgs.systemd}/bin/systemctl --user is-failed --quiet "$service"
    }

    start_service() {
      ${pkgs.systemd}/bin/systemctl --user reset-failed "$service" >/dev/null 2>&1 || true
      ${pkgs.systemd}/bin/systemctl --user start "$service" >/dev/null 2>&1
    }

    wait_for_daemon() {
      for _ in $(${pkgs.coreutils}/bin/seq 1 20); do
        if ${pkgs.iproute2}/bin/ss -tln 'sport = :8081' 2>/dev/null | ${pkgs.gnugrep}/bin/grep -q LISTEN; then
          return 0
        fi

        if service_has_failed; then
          return 2
        fi

        ${pkgs.coreutils}/bin/sleep 0.5
      done

      return 1
    }

    latest_spotify_log() {
      local log latest=""
      local logs=("$cache_dir"/spotify-player-*.log)

      if [ "''${#logs[@]}" -eq 0 ] || [ ! -e "''${logs[0]}" ]; then
        return 1
      fi

      for log in "''${logs[@]}"; do
        if [ -z "$latest" ] || [ "$log" -nt "$latest" ]; then
          latest="$log"
        fi
      done

      printf '%s\n' "$latest"
    }

    daemon_log_has_rate_limit() {
      local latest_log
      latest_log="$(latest_spotify_log)" || return 1
      ${pkgs.gnugrep}/bin/grep -Eq 'status code 429 Too Many Requests|"status":[[:space:]]*429|"message":[[:space:]]*"API rate limit exceeded"' "$latest_log"
    }

    run_auth() {
      ${pkgs.systemd}/bin/systemctl --user stop "$service" >/dev/null 2>&1 || true
      ${pkgs.systemd}/bin/systemctl --user reset-failed "$service" >/dev/null 2>&1 || true
      rm -f "$creds" "$web_token"
      echo "spotify_player: starting interactive Spotify login" >&2
      "$real_player" -c "${spotifyConfigDir}" authenticate
    }

    sync_client_id_cache

    # Explicit auth subcommand
    if [ "$#" -gt 0 ] && { [ "$1" = "auth" ] || [ "$1" = "authenticate" ]; }; then
      run_auth
      exit
    fi

    # Pass-through for anything that doesn't need the daemon
    if ! needs_daemon "$@"; then
      exec "$real_player" "$@"
    fi

    # Bootstrap credentials on first run
    if [ ! -s "$creds" ]; then
      echo "spotify_player: no cached Spotify credentials; starting interactive login" >&2
      run_auth
      auth_attempted=1
    fi

    # If cached credentials have gone stale, the daemon dies quickly with a
    # 400 refresh-token failure. Recover once by clearing the cached login and
    # re-running the interactive auth flow, but never probe with a CLI command
    # that could itself launch another browser tab.
    daemon_status=0
    if ! start_service; then
      echo "spotify_player: warning: $service failed to start; if Spotify rejects the cached login, run 'spotify_player authenticate'" >&2
    fi

    wait_for_daemon || daemon_status=$?

    if [ "$daemon_status" -eq 2 ] && [ "$auth_attempted" -eq 0 ] && [ -s "$creds" ]; then
      echo "spotify_player: cached Spotify login expired; re-authenticating..." >&2
      run_auth
      auth_attempted=1
      daemon_status=0

      if ! start_service; then
        echo "spotify_player: warning: $service failed to start after re-authentication" >&2
      fi

      wait_for_daemon || daemon_status=$?
    fi

    if [ "$daemon_status" -eq 1 ]; then
      echo "spotify_player: warning: $service did not become ready; the TUI may stay stuck in loading" >&2
    elif [ "$daemon_status" -eq 2 ]; then
      echo "spotify_player: warning: $service still fails after re-authentication; the TUI may stay stuck in loading" >&2
    fi

    if daemon_log_has_rate_limit; then
      if [ -s "$client_id_file" ]; then
        echo "spotify_player: warning: Spotify Web API is rate-limited for the current client ID; wait for Spotify's Retry-After window, then run 'spotify_player authenticate' if the TUI stays blank" >&2
      else
        echo "spotify_player: warning: Spotify Web API is rate-limited for the shared client ID; add your own Spotify app client ID to '$client_id_file' and rerun 'spotify_player authenticate' if the TUI stays blank" >&2
      fi
    fi

    exec "$real_player" "$@"
  '';
in {
  # TUI config: Always streaming so the TUI owns its own fresh librespot
  # device and can start playback immediately without a Connect transfer.
  # playback_refresh_duration_in_ms=0 means event-driven (librespot fires
  # events on playback changes, no periodic API polling needed).
  home.file."${spotifyConfigDir}/app.toml".text = ''
    enable_media_control = false
    enable_notify = false
    enable_streaming = "Always"
    playback_refresh_duration_in_ms = 0
    ${appTomlCommon}'';

  # Daemon config: Never streaming — only MPRIS and notifications.
  # The TUI owns the librespot device; the daemon mirrors playback state
  # for media keys and DMS widgets via periodic polling (no librespot events).
  home.file."${config.xdg.configHome}/spotify-player-daemon/app.toml".text = ''
    enable_media_control = true
    enable_notify = true
    notify_transient = true
    enable_streaming = "Never"
    playback_refresh_duration_in_ms = 5000
    ${appTomlCommon}'';

  programs.spotify-player = {
    enable = true;
    package = spotifyPlayerPkg;
  };

  # Keep the user-facing wrapper and the background daemon separate: the
  # wrapper bootstraps the service on demand, while systemd must launch the
  # raw binary directly to avoid recursive self-start.
  systemd.user.services.spotify-player = {
    Unit = {
      Description = "Spotify Player Daemon";
      After = ["network-online.target"];
      Wants = ["network-online.target"];
      StartLimitIntervalSec = 300;
      StartLimitBurst = 5;
    };
    Service = {
      Type = "forking";
      ExecStart = "${spotifyPlayerRawPkg}/bin/spotify_player ${spotifyDaemonArgs}";
      Restart = "on-failure";
      RestartSec = "15s";
      TimeoutStopSec = "5s";
    };
  };
}
