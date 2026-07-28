{
  pkgs,
  name,
  policyVersion,
  packageId,
  valueKey,
  allowedValues,
}: let
  inherit (pkgs) lib;
  allowedPattern = lib.concatStringsSep "|" allowedValues;
in ''
  render_policy_fingerprint_file="''${render_policy_fingerprint_file:-/run/system-manifest/host-fingerprint}"
  render_policy_cache_file=""
  render_policy_state_dir="''${XDG_STATE_HOME:-''${HOME:?HOME is required}/.local/state}/system-manifest/render-compat"

  if [ -r "$render_policy_fingerprint_file" ]; then
    IFS= read -r render_policy_fingerprint < "$render_policy_fingerprint_file" || true
    if [[ "$render_policy_fingerprint" =~ ^[0-9a-f]{64}$ ]]; then
      render_policy_cache_file="$render_policy_state_dir/${name}-$render_policy_fingerprint.conf"
      ${pkgs.coreutils}/bin/mkdir -p -- "$render_policy_state_dir"
      ${pkgs.coreutils}/bin/chmod 0700 "$render_policy_state_dir"
    fi
  fi

  render_policy_read() {
    local lines=()
    local value

    [ -n "$render_policy_cache_file" ] && [ -r "$render_policy_cache_file" ] || return 1
    mapfile -t lines < "$render_policy_cache_file" || return 1
    [ "''${#lines[@]}" -eq 3 ] || return 1
    [ "''${lines[0]}" = "policy=${policyVersion}" ] || return 1
    [ "''${lines[1]}" = "package=${packageId}" ] || return 1
    value="''${lines[2]#${valueKey}=}"
    [ "''${lines[2]}" = "${valueKey}=$value" ] || return 1
    case "$value" in
      ${allowedPattern})
        printf '%s\n' "$value"
        ;;
      *)
        return 1
        ;;
    esac
  }

  render_policy_write() {
    local value="$1"
    local cache_tmp

    [ -n "$render_policy_cache_file" ] || return 0
    case "$value" in
      ${allowedPattern}) ;;
      *) return 1 ;;
    esac

    ${pkgs.coreutils}/bin/mkdir -p -- "$render_policy_state_dir"
    ${pkgs.coreutils}/bin/chmod 0700 "$render_policy_state_dir"
    cache_tmp="$(${pkgs.coreutils}/bin/mktemp "$render_policy_cache_file.tmp.XXXXXX")" || return 1
    ${pkgs.coreutils}/bin/chmod 0600 "$cache_tmp"
    {
      printf 'policy=%s\n' '${policyVersion}'
      printf 'package=%s\n' '${packageId}'
      printf '%s=%s\n' '${valueKey}' "$value"
    } > "$cache_tmp"
    ${pkgs.coreutils}/bin/mv -f -- "$cache_tmp" "$render_policy_cache_file"
  }

  render_policy_clear() {
    [ -z "$render_policy_cache_file" ] ||
      ${pkgs.coreutils}/bin/rm -f -- "$render_policy_cache_file"
  }
''
