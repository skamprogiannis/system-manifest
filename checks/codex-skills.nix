{ctx}: let
  inherit (ctx) desktopCodexSkillsRoot pkgs;
  expectedSkills = [
    "browser-automation"
    "caveman"
    "caveman-commit"
    "caveman-review"
    "code-review"
    "codebase-design"
    "diagnose"
    "domain-modeling"
    "grill-with-docs"
    "grilling"
    "impeccable"
    "implement"
    "improve-codebase-architecture"
    "prototype"
    "setup-matt-pocock-skills"
    "static-analysis"
    "tdd"
    "technical-debt"
    "to-issues"
    "to-prd"
    "triage"
    "visual-explainer"
    "zoom-out"
  ];
  expectedSkillsJson = builtins.toFile "expected-codex-skills.json" (builtins.toJSON expectedSkills);
in {
  codex-skills =
    pkgs.runCommand "codex-skills-check" {
      nativeBuildInputs = [
        pkgs.nodejs
        pkgs.python3
      ];
    } ''
      set -euo pipefail

      skills_root="${desktopCodexSkillsRoot}"

      python3 - "$skills_root" ${expectedSkillsJson} <<'PY'
      from pathlib import Path
      import json
      import re
      import sys

      root = Path(sys.argv[1])
      expected = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
      actual = sorted(path.name for path in root.iterdir() if path.is_dir())

      if actual != expected:
          missing = sorted(set(expected) - set(actual))
          unexpected = sorted(set(actual) - set(expected))
          raise SystemExit(
              "Codex skill catalog mismatch\n"
              f"  missing: {missing}\n"
              f"  unexpected: {unexpected}"
          )

      link_pattern = re.compile(r"\[[^\]]*\]\(([^)]+)\)")
      name_pattern = re.compile(r"^name:\s*['\"]?([^'\"\n]+)", re.MULTILINE)
      placeholder_pattern = re.compile(r"\{\{[A-Za-z_][^}]*\}\}")

      for name in actual:
          skill_dir = root / name
          skill_file = skill_dir / "SKILL.md"
          if not skill_file.is_file():
              raise SystemExit(f"Missing readable SKILL.md for {name}: {skill_file}")

          text = skill_file.read_text(encoding="utf-8")
          match = name_pattern.search(text)
          if match is None or match.group(1).strip() != name:
              found = None if match is None else match.group(1).strip()
              raise SystemExit(f"Skill name mismatch for {name}: found {found!r}")

          placeholder = placeholder_pattern.search(text)
          if placeholder is not None:
              raise SystemExit(
                  f"Unrendered provider placeholder in {skill_file}: {placeholder.group(0)}"
              )

          for raw_target in link_pattern.findall(text):
              target = raw_target.strip().split("#", 1)[0]
              if not target or target.startswith(("#", "/", "http://", "https://", "mailto:")):
                  continue
              if not target.startswith(("./", "../")) and not Path(target).suffix:
                  continue
              resolved = skill_dir / target
              if not resolved.exists():
                  raise SystemExit(
                      f"Missing relative skill resource in {skill_file}: {raw_target}"
                  )
      PY

      impeccable_log="$TMPDIR/impeccable-context.log"
      HOME="$TMPDIR/home" node "$skills_root/impeccable/scripts/context.mjs" \
        --target "$TMPDIR" >"$impeccable_log"
      if ! grep -Eq 'NO_PRODUCT_MD|RESOLVED_CONTEXT' "$impeccable_log"; then
        echo "Impeccable Codex context script did not produce a recognized result." >&2
        sed 's/^/  /' "$impeccable_log" >&2
        exit 1
      fi

      touch "$out"
    '';
}
