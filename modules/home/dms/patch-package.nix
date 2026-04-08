{pkgs}: {
  package,
  pythonPrelude ? "",
  replacementsPython,
}:
package.overrideAttrs (old: {
  postInstall =
    (old.postInstall or "")
    + ''
          ${pkgs.python3}/bin/python3 - <<PY
      from pathlib import Path
      import stat

      root = Path("$out/share/quickshell/dms")
      ${pythonPrelude}
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
