{ctx}: let
  inherit (ctx) desktopPinchtabPackage desktopCodexSkillsRoot desktopPinchtabConfigActivationFile pkgs;
  expectedSkills = [
    "browser-automation"
    "caveman"
    "caveman-commit"
    "caveman-review"
    "clef-decisions"
    "code-review"
    "codebase-design"
    "diagnose"
    "domain-modeling"
    "grilling"
    "impeccable"
    "prototype"
    "static-analysis"
    "tdd"
    "technical-debt"
    "visual-explainer"
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

          if name in {"code-review", "tdd"} and "Skill tool" in text:
              raise SystemExit(f"Codex-incompatible Skill tool instruction in {skill_file}")
          if name == "code-review" and "/setup-matt-pocock-skills" in text:
              raise SystemExit(f"Obsolete setup workflow in {skill_file}")
      PY

      test -x "$skills_root/impeccable/scripts/impeccable"
      test -f "$skills_root/impeccable/reference/generate.md"
      test -x "$skills_root/impeccable/scripts/bin/linux-x64/impeccable"
      impeccable_version="$(tr -d '[:space:]' < "$skills_root/impeccable/scripts/VERSION")"
      # Probe mode refuses runtime downloads and skips user cache/PATH fallbacks.
      test "$(IMPECCABLE_LAUNCHER_PROBE=1 "$skills_root/impeccable/scripts/impeccable" engine-probe)" = "impeccable-engine $impeccable_version"
      test -f "$skills_root/browser-automation/references/safety.md"
      test -f "$skills_root/browser-automation/agents/openai.yaml"

      pinchtab_seed="$(sed -n 's|^[[:space:]]*cp \(/nix/store/[^ ]*pinchtab-config.json\) .*|\1|p' ${desktopPinchtabConfigActivationFile})"
      test -n "$pinchtab_seed"
      PINCHTAB_CONFIG="$pinchtab_seed" "${desktopPinchtabPackage}/bin/pinchtab" config validate

      touch "$out"
    '';
}
