{ctx}: let
  inherit
    (ctx)
    desktopSpotifyDesktopEntryNames
    desktopSpotifyDesktopExec
    desktopSpotifyLauncherPackage
    desktopSpotifyPackage
    desktopSpotifyPackageClosure
    pkgs
    ;
  fakeSpotify = pkgs.writeShellScript "fake-spotify" ''
    set -euo pipefail

    trace="''${SYSTEM_MANIFEST_SPOTIFY_FAKE_TRACE:?}"
    scenario="''${SYSTEM_MANIFEST_SPOTIFY_FAKE_SCENARIO:?}"
    {
      printf 'call'
      printf ' <%s>' "$@"
      printf '\n'
    } >> "$trace"

    has_disable_gpu=false
    for argument in "$@"; do
      if [ "$argument" = "--disable-gpu" ]; then
        has_disable_gpu=true
        break
      fi
    done

    run_signal_fixture() {
      signal_dir="''${SYSTEM_MANIFEST_SPOTIFY_SIGNAL_DIR:?}"
      (
        trap 'printf "TERM\n" > "$signal_dir/child"; exit 0' TERM
        touch "$signal_dir/child-ready"
        while true; do
          sleep 0.1
        done
      ) &
      descendant="$!"
      trap 'printf "TERM\n" > "$signal_dir/main"; wait "$descendant" || true; exit 143' TERM
      touch "$signal_dir/main-ready"
      wait "$descendant"
    }

    case "$scenario" in
      success)
        exit 0
        ;;
      gpu-fatal)
        if [ "$has_disable_gpu" = true ]; then
          exit 0
        fi
        echo "[FATAL:gpu_data_manager_impl_private.cc:417] GPU process isn't usable. Goodbye." >&2
        exit 133
        ;;
      gpu-fatal-live)
        if [ "$has_disable_gpu" = true ]; then
          run_signal_fixture
          exit 0
        fi
        echo "[FATAL:gpu_data_manager_impl_private.cc:417] GPU process isn't usable. Goodbye." >&2
        exit 133
        ;;
      gpu-fatal-zero)
        echo "[FATAL:gpu_data_manager_impl_private.cc:417] GPU process isn't usable. Goodbye." >&2
        exit 0
        ;;
      mesa-abi)
        echo "MESA-LOADER: failed to open dri" >&2
        echo "libc.so.6: version 'GLIBC_ABI_GNU2_TLS' not found" >&2
        echo "[FATAL:gpu_data_manager_impl_private.cc:417] GPU process isn't usable. Goodbye." >&2
        exit 133
        ;;
      vulkan)
        echo "Warning: vkCreateInstance: Found no drivers!" >&2
        echo "Warning: vkCreateInstance failed with VK_ERROR_INCOMPATIBLE_DRIVER" >&2
        exit 42
        ;;
      signal)
        run_signal_fixture
        ;;
      *)
        echo "Unknown fake Spotify scenario: $scenario" >&2
        exit 2
        ;;
    esac
  '';
  fakeNotify = pkgs.writeShellScript "fake-notify" ''
    set -euo pipefail
    printf '%s\n' "$*" >> "''${SYSTEM_MANIFEST_SPOTIFY_NOTIFY_TRACE:?}"
  '';
in {
  spotify-runtime =
    pkgs.runCommand "spotify-runtime-checks" {
      nativeBuildInputs = [
        pkgs.coreutils
        pkgs.findutils
        pkgs.gnugrep
        pkgs.gnused
      ];
    } ''
      set -euo pipefail

      closure_paths=${desktopSpotifyPackageClosure}/store-paths
      launcher=${desktopSpotifyLauncherPackage}/bin/spotify

      if [ "${desktopSpotifyPackage.version}" != "1.2.63.394.g126b0d89" ]; then
        echo "Expected the authenticated known-good Spotify 1.2.63 payload." >&2
        exit 1
      fi

      if ! grep -Fxq ${pkgs.glibc} "$closure_paths"; then
        echo "Spotify must use the current Nixpkgs glibc runtime." >&2
        grep -- '-glibc-' "$closure_paths" >&2 || true
        exit 1
      fi

      if grep -Fq -- '-glibc-2.40-' "$closure_paths"; then
        echo "Spotify still closes over the pinned Nixpkgs glibc 2.40 runtime." >&2
        grep -- '-glibc-' "$closure_paths" >&2 || true
        exit 1
      fi

      if [ ${builtins.toJSON desktopSpotifyDesktopExec} != "spotify %U" ]; then
        echo "The standard Spotify desktop entry no longer launches the spotify command." >&2
        exit 1
      fi

      if [ "$(cat ${desktopSpotifyDesktopEntryNames})" != '["spotify"]' ]; then
        echo "Expected exactly one declarative Spotify desktop entry." >&2
        cat ${desktopSpotifyDesktopEntryNames} >&2
        exit 1
      fi

      run_case() {
        local case_root="$1"
        local scenario="$2"
        shift 2

        mkdir -p "$case_root/home" "$case_root/state"
        printf 'test-host-fingerprint\n' > "$case_root/fingerprint"
        : > "$case_root/trace"
        : > "$case_root/notify"

        HOME="$case_root/home" \
          XDG_STATE_HOME="$case_root/state" \
          SYSTEM_MANIFEST_SPOTIFY_TEST_MODE=1 \
          SYSTEM_MANIFEST_SPOTIFY_REAL_BIN=${fakeSpotify} \
          SYSTEM_MANIFEST_SPOTIFY_FINGERPRINT_FILE="$case_root/fingerprint" \
          SYSTEM_MANIFEST_SPOTIFY_NOTIFY_BIN=${fakeNotify} \
          SYSTEM_MANIFEST_SPOTIFY_NOTIFY_TRACE="$case_root/notify" \
          SYSTEM_MANIFEST_SPOTIFY_FAKE_TRACE="$case_root/trace" \
          SYSTEM_MANIFEST_SPOTIFY_FAKE_SCENARIO="$scenario" \
          SYSTEM_MANIFEST_SPOTIFY_HEALTHY_SECONDS=0.1 \
          "$launcher" "$@"
      }

      success_root="$TMPDIR/success"
      run_case "$success_root" success "spotify:track:test"
      if [ "$(wc -l < "$success_root/trace")" -ne 1 ] \
        || ! grep -Fq '<spotify:track:test>' "$success_root/trace"; then
        echo "Spotify launcher did not preserve a successful invocation and its arguments." >&2
        cat "$success_root/trace" >&2
        exit 1
      fi

      gpu_root="$TMPDIR/gpu"
      run_case "$gpu_root" gpu-fatal
      if [ "$(wc -l < "$gpu_root/trace")" -ne 2 ]; then
        echo "Exact fatal GPU failure must cause exactly one retry." >&2
        cat "$gpu_root/trace" >&2
        exit 1
      fi
      if ! sed -n '2p' "$gpu_root/trace" | grep -Fq '<--disable-gpu>'; then
        echo "Fatal GPU retry did not enable software rendering." >&2
        cat "$gpu_root/trace" >&2
        exit 1
      fi

      cache_file="$(find "$gpu_root/state/system-manifest/render-compat" -name 'spotify-*.conf' -print -quit)"
      if [ -z "$cache_file" ]; then
        echo "Successful software fallback was not cached." >&2
        exit 1
      fi

      : > "$gpu_root/trace"
      run_case "$gpu_root" gpu-fatal
      if [ "$(wc -l < "$gpu_root/trace")" -ne 1 ] \
        || ! grep -Fq '<--disable-gpu>' "$gpu_root/trace"; then
        echo "Cached software mode was not used on the next launch." >&2
        cat "$gpu_root/trace" >&2
        exit 1
      fi

      sed -i 's/^policy=.*/policy=stale/' "$cache_file"
      : > "$gpu_root/trace"
      run_case "$gpu_root" gpu-fatal
      if [ "$(wc -l < "$gpu_root/trace")" -ne 2 ] \
        || grep -Fq '<--disable-gpu>' < <(sed -n '1p' "$gpu_root/trace"); then
        echo "A stale render-policy cache must re-probe normal GPU mode." >&2
        cat "$gpu_root/trace" >&2
        exit 1
      fi

      zero_root="$TMPDIR/zero"
      run_case "$zero_root" gpu-fatal-zero
      if [ "$(wc -l < "$zero_root/trace")" -ne 1 ]; then
        echo "GPU fatal text from a successful process must not trigger a retry." >&2
        cat "$zero_root/trace" >&2
        exit 1
      fi

      abi_root="$TMPDIR/abi"
      if run_case "$abi_root" mesa-abi; then
        echo "Mesa/glibc ABI fixture unexpectedly succeeded." >&2
        exit 1
      else
        status="$?"
      fi
      if [ "$status" -ne 133 ] \
        || [ "$(wc -l < "$abi_root/trace")" -ne 1 ] \
        || ! grep -Fq 'Spotify packaging error' "$abi_root/notify"; then
        echo "Mesa/glibc ABI failure must notify without retrying." >&2
        cat "$abi_root/trace" "$abi_root/notify" >&2
        exit 1
      fi

      vulkan_root="$TMPDIR/vulkan"
      if run_case "$vulkan_root" vulkan; then
        echo "Vulkan warning fixture unexpectedly succeeded." >&2
        exit 1
      else
        status="$?"
      fi
      if [ "$status" -ne 42 ] || [ "$(wc -l < "$vulkan_root/trace")" -ne 1 ]; then
        echo "Generic Vulkan warnings must not trigger a software retry." >&2
        cat "$vulkan_root/trace" >&2
        exit 1
      fi

      signal_root="$TMPDIR/signal"
      mkdir -p "$signal_root/home" "$signal_root/state" "$signal_root/signals"
      printf 'test-host-fingerprint\n' > "$signal_root/fingerprint"
      : > "$signal_root/trace"
      : > "$signal_root/notify"
      HOME="$signal_root/home" \
        XDG_STATE_HOME="$signal_root/state" \
        SYSTEM_MANIFEST_SPOTIFY_TEST_MODE=1 \
        SYSTEM_MANIFEST_SPOTIFY_REAL_BIN=${fakeSpotify} \
        SYSTEM_MANIFEST_SPOTIFY_FINGERPRINT_FILE="$signal_root/fingerprint" \
        SYSTEM_MANIFEST_SPOTIFY_NOTIFY_BIN=${fakeNotify} \
        SYSTEM_MANIFEST_SPOTIFY_NOTIFY_TRACE="$signal_root/notify" \
        SYSTEM_MANIFEST_SPOTIFY_FAKE_TRACE="$signal_root/trace" \
        SYSTEM_MANIFEST_SPOTIFY_FAKE_SCENARIO=gpu-fatal-live \
        SYSTEM_MANIFEST_SPOTIFY_SIGNAL_DIR="$signal_root/signals" \
        SYSTEM_MANIFEST_SPOTIFY_HEALTHY_SECONDS=0.1 \
        "$launcher" &
      wrapper_pid="$!"

      for _ in $(seq 1 100); do
        if [ -e "$signal_root/signals/main-ready" ] \
          && [ -e "$signal_root/signals/child-ready" ]; then
          break
        fi
        sleep 0.05
      done
      if [ ! -e "$signal_root/signals/main-ready" ] \
        || [ ! -e "$signal_root/signals/child-ready" ]; then
        echo "Signal fixture did not become ready." >&2
        kill -KILL "$wrapper_pid" 2>/dev/null || true
        exit 1
      fi

      signal_cache=""
      for _ in $(seq 1 100); do
        signal_cache="$(find "$signal_root/state/system-manifest/render-compat" -name 'spotify-*.conf' -print -quit)"
        if [ -n "$signal_cache" ]; then
          break
        fi
        sleep 0.05
      done
      if [ -z "$signal_cache" ]; then
        echo "A healthy software fallback was not cached before process exit." >&2
        kill -KILL "$wrapper_pid" 2>/dev/null || true
        exit 1
      fi

      kill -TERM "$wrapper_pid"
      set +e
      wait "$wrapper_pid"
      status="$?"
      set -e
      if [ "$status" -ne 143 ] \
        || [ "$(cat "$signal_root/signals/main")" != "TERM" ] \
        || [ "$(cat "$signal_root/signals/child")" != "TERM" ] \
        || [ ! -f "$signal_cache" ]; then
        echo "TERM was not forwarded to the full process group or cleared a healthy cache." >&2
        find "$signal_root/signals" -maxdepth 1 -type f -print -exec cat {} \; >&2
        exit 1
      fi

      touch "$out"
    '';
}
