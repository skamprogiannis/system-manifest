{
  lib,
  pkgs,
  ...
}: let
  managedTheme = builtins.toJSON {
    features.matugen = true;
    theme = {
      policy = "wallpaper";
      authority = "skwd";
      engine = "matugen";
      targets = ["dms"];
    };
  };
in {
  # skwd-wall v2 owns wallpaper-derived colour generation. Keep the rest of its
  # runtime/UI configuration user-editable while declaratively pinning the
  # shared colour pipeline used by DMS and Vesktop.
  home.activation.configureSkwdWallV2Theming = lib.hm.dag.entryAfter ["writeBoundary"] ''
    config_dir="$HOME/.config/skwd-wall-v2"
    config_file="$config_dir/config.json"
    mkdir -p "$config_dir"

    tmp=$(${pkgs.coreutils}/bin/mktemp "$config_dir/.config.json.XXXXXX")
    trap '${pkgs.coreutils}/bin/rm -f "$tmp"' EXIT

    if [ -s "$config_file" ]; then
      if ${pkgs.jq}/bin/jq empty "$config_file" >/dev/null 2>&1; then
        ${pkgs.jq}/bin/jq --argjson managed '${managedTheme}' '. * $managed' "$config_file" > "$tmp"
      else
        echo "configureSkwdWallV2Theming: backing up malformed $config_file" >&2
        ${pkgs.coreutils}/bin/cp -f "$config_file" "$config_file.invalid"
        printf '%s\n' '${managedTheme}' > "$tmp"
      fi
    else
      printf '%s\n' '${managedTheme}' > "$tmp"
    fi

    ${pkgs.coreutils}/bin/chmod 600 "$tmp"
    ${pkgs.coreutils}/bin/mv -f "$tmp" "$config_file"
    trap - EXIT
  '';
}
