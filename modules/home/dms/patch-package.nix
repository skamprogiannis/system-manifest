{pkgs}: {
  package,
  replacementsPython,
}:
package.overrideAttrs (old: {
  # Home Manager wraps Lua keys/actions in parentheses; DMS must read those
  # declarative bindings without taking over their ownership.
  patches = (old.patches or []) ++ [./hyprland-parentheses.patch];
  postCheck =
    (old.postCheck or "")
    + ''
      go test ./internal/keybinds/providers
    '';
  postInstall =
    (old.postInstall or "")
    + ''
          ${pkgs.python3}/bin/python3 - <<'PY'
      from pathlib import Path
      import os
      import stat

      root = Path(os.environ["out"]) / "share/quickshell/dms"
      replacements = {
      ${replacementsPython}
      }

      for path, edits in replacements.items():
          path.chmod(path.stat().st_mode | stat.S_IWUSR)
          text = path.read_text(encoding="utf-8")
          for old, new in edits:
              if old not in text:
                  raise SystemExit(f"Expected snippet not found in {path}: {old}")
              text = text.replace(old, new, 1)
          path.write_text(text, encoding="utf-8")
          path.chmod(path.stat().st_mode & ~stat.S_IWUSR & ~stat.S_IWGRP & ~stat.S_IWOTH)
      PY
    '';
})
