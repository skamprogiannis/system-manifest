{
  proton-vpn,
  python3,
}:
proton-vpn.overrideAttrs (old: {
  patches = (old.patches or []) ++ [./icon-pixmap.patch];

  postInstallCheck =
    (old.postInstallCheck or "")
    + ''
      (cd "$out"
       export XDG_RUNTIME_DIR="$(mktemp -d)"
       export XDG_CACHE_HOME="$XDG_RUNTIME_DIR/cache"
       export XDG_CONFIG_HOME="$XDG_RUNTIME_DIR/config"
       PYTHONPATH="$out/${python3.sitePackages}:$PYTHONPATH" \
         ${python3.interpreter} ${./tray-properties.py})
    '';
})
