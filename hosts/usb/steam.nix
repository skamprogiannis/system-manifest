{
  lib,
  pkgs,
  ...
}: let
  steamDir = "/nix/.host-scratch/user/stefan/steam/Steam";
  persistentSteamDir = "/home/stefan/.local/share/Steam";
  bootstrap = "${pkgs.steam-unwrapped}/lib/steam/bootstraplinux_ubuntu12_32.tar.xz";
  prepareHostScratchSteam = pkgs.writeShellScript "prepare-host-scratch-steam" ''
    set -eu

    mode_file=/run/usb-host-scratch.mode
    steam_dir=${lib.escapeShellArg steamDir}
    persistent_steam_dir=${lib.escapeShellArg persistentSteamDir}
    bootstrap=${lib.escapeShellArg bootstrap}
    state_marker="$steam_dir/.system-manifest-state-imported"

    if [ ! -f "$mode_file" ] ||
      ! ${pkgs.gnugrep}/bin/grep -qx "encrypted-host-scratch" "$mode_file"; then
      exit 0
    fi

    ${pkgs.coreutils}/bin/mkdir -p "$steam_dir" "$HOME/.steam"

    if [ ! -x "$steam_dir/steam.sh" ]; then
      ${pkgs.gnutar}/bin/tar --use-compress-program=${pkgs.xz}/bin/xz -xf "$bootstrap" -C "$steam_dir"
    fi

    if [ ! -e "$state_marker" ]; then
      for state_dir in config userdata; do
        if [ -d "$persistent_steam_dir/$state_dir" ]; then
          ${pkgs.coreutils}/bin/mkdir -p "$steam_dir/$state_dir"
          ${pkgs.rsync}/bin/rsync -a \
            "$persistent_steam_dir/$state_dir/" \
            "$steam_dir/$state_dir/"
        fi
      done
      if [ -d "$persistent_steam_dir" ]; then
        ${pkgs.rsync}/bin/rsync -a \
          --include='ssfn*' \
          --exclude='*' \
          "$persistent_steam_dir/" \
          "$steam_dir/"
      fi
      ${pkgs.coreutils}/bin/touch "$state_marker"
    fi

    for link_name in steam root; do
      link_path="$HOME/.steam/$link_name"
      if [ -e "$link_path" ] && [ ! -L "$link_path" ]; then
        echo "steam: refusing to replace non-symlink $link_path" >&2
        exit 1
      fi
      ${pkgs.coreutils}/bin/ln -sfnT "$steam_dir" "$link_path"
    done
  '';
in {
  options.systemManifest.usb.steamHostScratch.prepareScript = lib.mkOption {
    type = lib.types.package;
    default = prepareHostScratchSteam;
    internal = true;
    readOnly = true;
    description = "Internal host-auto Steam preparation script exposed for integration checks.";
  };

  config = {
    programs.steam.enable = true;
    programs.gamemode.enable = true;
    systemd.tmpfiles.rules = [
      "d /home/stefan/games/SteamLibrary 0755 stefan users - -"
    ];

    specialisation.host-auto-store.configuration.programs.steam.package = pkgs.steam.override {
      extraPreBwrapCmds = ''
        ${prepareHostScratchSteam} || exit $?
      '';
    };
  };
}
