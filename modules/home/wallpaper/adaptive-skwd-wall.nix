{
  pkgs,
  skwdWallPackage,
}: let
  policyVersion = "1";
  launcherTemplate = pkgs.writeText "skwd-wall-adaptive-launcher" ''
    #!${pkgs.bash}/bin/bash
    set -u

    policy_version="${policyVersion}"
    render_failure_status=70
    package_id="@packageId@"
    renderer="''${SKWD_WALL_RENDERER_BIN:-${skwdWallPackage}/bin/skwd-wall}"
    fingerprint_file="''${SYSTEM_MANIFEST_HOST_FINGERPRINT_FILE:-/run/system-manifest/host-fingerprint}"
    state_root="''${XDG_STATE_HOME:-$HOME/.local/state}"
    cache_dir="$state_root/system-manifest/render-compat"
    cache_file=""
    child_pid=""
    tee_pid=""
    attempt_dir=""
    terminate_requested=0

    fingerprint=""
    if [ -r "$fingerprint_file" ]; then
      IFS= read -r fingerprint < "$fingerprint_file" || true
      if [[ ! "$fingerprint" =~ ^[0-9a-f]{64}$ ]]; then
        fingerprint=""
      fi
    fi

    if [ -n "$fingerprint" ]; then
      cache_file="$cache_dir/skwd-wall-$fingerprint.backend"
    fi

    stop_child() {
      local signal="$1"

      if [ -n "$child_pid" ] && ${pkgs.coreutils}/bin/kill -0 "$child_pid" 2>/dev/null; then
        ${pkgs.coreutils}/bin/kill "-$signal" "$child_pid" 2>/dev/null || true
      fi
    }

    stop_tee() {
      if [ -n "$tee_pid" ] && ${pkgs.coreutils}/bin/kill -0 "$tee_pid" 2>/dev/null; then
        ${pkgs.coreutils}/bin/kill -TERM "$tee_pid" 2>/dev/null || true
      fi
    }

    forward_signal() {
      local signal="$1"

      terminate_requested=1
      stop_child "$signal"
      for _ in $(${pkgs.coreutils}/bin/seq 1 20); do
        if [ -z "$child_pid" ] || ! ${pkgs.coreutils}/bin/kill -0 "$child_pid" 2>/dev/null; then
          return
        fi
        ${pkgs.coreutils}/bin/sleep 0.1
      done
      stop_child KILL
    }

    cleanup_attempt() {
      stop_child TERM
      if [ -n "$child_pid" ]; then
        wait "$child_pid" 2>/dev/null || true
      fi
      if [ -n "$tee_pid" ]; then
        stop_tee
        wait "$tee_pid" 2>/dev/null || true
      fi
      if [ -n "$attempt_dir" ] && [ -d "$attempt_dir" ]; then
        ${pkgs.coreutils}/bin/rm -rf -- "$attempt_dir"
      fi
      child_pid=""
      tee_pid=""
      attempt_dir=""
    }

    trap 'forward_signal TERM' TERM
    trap 'forward_signal INT' INT
    trap 'forward_signal QUIT' QUIT
    trap cleanup_attempt EXIT

    read_cached_backend() {
      local lines=()

      [ -n "$cache_file" ] && [ -r "$cache_file" ] || return 1
      mapfile -t lines < "$cache_file" || return 1
      [ "''${#lines[@]}" -eq 3 ] || return 1
      [ "''${lines[0]}" = "policy=$policy_version" ] || return 1
      [ "''${lines[1]}" = "package=$package_id" ] || return 1
      case "''${lines[2]}" in
        backend=opengl)
          printf '%s\n' opengl
          ;;
        backend=software)
          printf '%s\n' software
          ;;
        *)
          return 1
          ;;
      esac
    }

    cache_backend() {
      local backend="$1"
      local cache_tmp

      [ -n "$cache_file" ] || return 0
      ${pkgs.coreutils}/bin/mkdir -p -- "$cache_dir"
      cache_tmp="$(${pkgs.coreutils}/bin/mktemp "$cache_file.tmp.XXXXXX")" || return 0
      ${pkgs.coreutils}/bin/chmod 0600 "$cache_tmp"
      {
        printf 'policy=%s\n' "$policy_version"
        printf 'package=%s\n' "$package_id"
        printf 'backend=%s\n' "$backend"
      } > "$cache_tmp"
      ${pkgs.coreutils}/bin/mv -f -- "$cache_tmp" "$cache_file"
    }

    has_render_failure() {
      ${pkgs.gnugrep}/bin/grep -Fq \
        -e "Failed to create RHI" \
        -e "Failed to initialize graphics backend" \
        "$attempt_dir/stderr.log"
    }

    run_attempt() {
      local backend="$1"
      shift
      local fifo
      local status
      local render_failure=0
      local success_ticks=0
      local cached=0
      local renderer_command=(
        ${pkgs.util-linux}/bin/setpriv
        --pdeathsig KILL
        --
        ${pkgs.python3}/bin/python3
        -c
        'import os, signal, sys; signals = (signal.SIGINT, signal.SIGTERM, signal.SIGQUIT); [signal.signal(sig, signal.SIG_DFL) for sig in signals]; signal.pthread_sigmask(signal.SIG_UNBLOCK, signals); os.execvpe(sys.argv[1], sys.argv[1:], os.environ)'
        "$renderer"
        "$@"
      )

      attempt_dir="$(${pkgs.coreutils}/bin/mktemp -d "''${TMPDIR:-/tmp}/skwd-wall-render.XXXXXX")" || return 1
      fifo="$attempt_dir/stderr.fifo"
      : > "$attempt_dir/stderr.log"
      ${pkgs.coreutils}/bin/mkfifo "$fifo"
      ${pkgs.util-linux}/bin/setpriv --pdeathsig KILL -- \
        ${pkgs.coreutils}/bin/tee "$attempt_dir/stderr.log" < "$fifo" >&2 &
      tee_pid=$!

      if [ "$backend" = software ]; then
        ${pkgs.coreutils}/bin/env \
          QSG_RHI_BACKEND=opengl \
          QT_QUICK_BACKEND=software \
          "''${renderer_command[@]}" 2> "$fifo" &
      else
        ${pkgs.coreutils}/bin/env \
          -u QT_QUICK_BACKEND \
          QSG_RHI_BACKEND=opengl \
          "''${renderer_command[@]}" 2> "$fifo" &
      fi
      child_pid=$!

      if [ "$terminate_requested" -eq 1 ]; then
        stop_child TERM
      fi

      while ${pkgs.coreutils}/bin/kill -0 "$child_pid" 2>/dev/null; do
        if has_render_failure; then
          render_failure=1
          stop_child TERM
          break
        fi

        if [ "$cached" -eq 0 ] && [ "$success_ticks" -ge 20 ]; then
          cache_backend "$backend"
          cached=1
        fi
        success_ticks=$((success_ticks + 1))
        ${pkgs.coreutils}/bin/sleep 0.1
      done

      if [ "$render_failure" -eq 1 ]; then
        for _ in $(${pkgs.coreutils}/bin/seq 1 20); do
          if ! ${pkgs.coreutils}/bin/kill -0 "$child_pid" 2>/dev/null; then
            break
          fi
          ${pkgs.coreutils}/bin/sleep 0.05
        done
        if ${pkgs.coreutils}/bin/kill -0 "$child_pid" 2>/dev/null; then
          stop_child KILL
        fi
      fi

      if wait "$child_pid"; then
        status=0
      else
        status=$?
      fi
      child_pid=""

      for _ in $(${pkgs.coreutils}/bin/seq 1 20); do
        if ! ${pkgs.coreutils}/bin/kill -0 "$tee_pid" 2>/dev/null; then
          break
        fi
        ${pkgs.coreutils}/bin/sleep 0.01
      done
      stop_tee
      wait "$tee_pid" 2>/dev/null || true
      tee_pid=""

      if [ "$render_failure" -eq 0 ] && has_render_failure; then
        render_failure=1
      fi

      ${pkgs.coreutils}/bin/rm -rf -- "$attempt_dir"
      attempt_dir=""

      if [ "$render_failure" -eq 1 ]; then
        return "$render_failure_status"
      fi
      if [ "$status" -eq 0 ] && [ "$cached" -eq 0 ] && [ "$terminate_requested" -eq 0 ]; then
        cache_backend "$backend"
      fi
      return "$status"
    }

    backend="$(read_cached_backend || printf '%s\n' opengl)"
    run_attempt "$backend" "$@"
    status=$?

    if [ "$status" -eq "$render_failure_status" ] && [ "$backend" = opengl ] && [ "$terminate_requested" -eq 0 ]; then
      if [ -n "$cache_file" ]; then
        ${pkgs.coreutils}/bin/rm -f -- "$cache_file"
      fi
      run_attempt software "$@"
      status=$?
    elif [ "$status" -eq "$render_failure_status" ] && [ -n "$cache_file" ]; then
      ${pkgs.coreutils}/bin/rm -f -- "$cache_file"
    fi

    exit "$status"
  '';
in
  pkgs.runCommand "skwd-wall-adaptive" {} ''
    cp -rL ${skwdWallPackage} "$out"
    chmod -R u+w "$out"
    substitute ${launcherTemplate} "$out/bin/skwd-wall" \
      --replace-fail '@packageId@' "$out"
    chmod 0555 "$out/bin/skwd-wall"
  ''
