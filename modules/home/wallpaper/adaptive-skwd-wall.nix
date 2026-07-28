{
  pkgs,
  skwdWallPackage,
}: let
  policyVersion = "1";
  renderPolicy = import ../render-compat/policy.nix {
    inherit pkgs;
    name = "skwd-wall";
    inherit policyVersion;
    packageId = "@packageId@";
    valueKey = "backend";
    allowedValues = ["opengl" "software"];
  };
  launcherTemplate = pkgs.writeText "skwd-wall-adaptive-launcher" ''
    #!${pkgs.bash}/bin/bash
    set -u

    render_failure_status=70
    renderer="''${SKWD_WALL_RENDERER_BIN:-${skwdWallPackage}/bin/skwd-wall}"
    render_policy_fingerprint_file="''${SYSTEM_MANIFEST_HOST_FINGERPRINT_FILE:-/run/system-manifest/host-fingerprint}"
    child_pid=""
    tee_pid=""
    attempt_dir=""
    terminate_requested=0

    ${renderPolicy}

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
          render_policy_write "$backend"
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
        render_policy_write "$backend"
      fi
      return "$status"
    }

    backend="$(render_policy_read || printf '%s\n' opengl)"
    run_attempt "$backend" "$@"
    status=$?

    if [ "$status" -eq "$render_failure_status" ] && [ "$backend" = opengl ] && [ "$terminate_requested" -eq 0 ]; then
      render_policy_clear
      run_attempt software "$@"
      status=$?
    elif [ "$status" -eq "$render_failure_status" ]; then
      render_policy_clear
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
