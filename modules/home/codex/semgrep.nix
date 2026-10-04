{pkgs}: let
  upstream = pkgs.semgrep;
in
  if upstream.version == "1.172.0"
  then
    upstream.overridePythonAttrs (old: {
      # This release pins PyJWT 2.13 while Nixpkgs supplies 2.14 through MCP.
      # Keep the supported major version and return to stock on the next release.
      postPatch =
        (old.postPatch or "")
        + ''
          substituteInPlace pyproject.toml \
            --replace-fail 'pyjwt[crypto]~=2.13.0' 'pyjwt[crypto]>=2.13.0,<3'
        '';
      postCheck =
        (old.postCheck or "")
        + ''
          ${pkgs.python3.interpreter} ${./semgrep-jwt-check.py}
        '';
    })
  else upstream
