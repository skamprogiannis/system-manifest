{ctx}: let
  inherit (ctx) desktopPinchtabPackage desktopCodexSkillsRoot desktopPinchtabConfigActivationFile pkgs;
  expectedSkills = [
    "browser-automation"
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
      import subprocess
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

      browser_text = (root / "browser-automation/SKILL.md").read_text(encoding="utf-8")
      for command in ("wait", "console", "errors"):
          examples = re.findall(rf"^pinchtab {command}\b[^\n]*", browser_text, re.MULTILINE)
          if command == "wait":
              examples += re.findall(r"^Timeout [^\n]*", browser_text, re.MULTILINE)
          documented_flags = set(re.findall(r"--[a-z][a-z-]*", "\n".join(examples)))
          help_text = subprocess.check_output(
              ["${desktopPinchtabPackage}/bin/pinchtab", command, "--help"], text=True,
          )
          available_flags = set(re.findall(r"--[a-z][a-z-]*", help_text))
          unsupported = documented_flags - available_flags
          if unsupported:
              raise SystemExit(f"Unsupported PinchTab {command} flags in skill: {sorted(unsupported)}")
      PY

      test -x "$skills_root/impeccable/scripts/impeccable"
      test -f "$skills_root/impeccable/reference/generate.md"
      test -x "$skills_root/impeccable/scripts/bin/linux-x64/impeccable"
      impeccable_version="$(tr -d '[:space:]' < "$skills_root/impeccable/scripts/VERSION")"
      # Probe mode refuses runtime downloads and skips user cache/PATH fallbacks.
      test "$(IMPECCABLE_LAUNCHER_PROBE=1 "$skills_root/impeccable/scripts/impeccable" engine-probe)" = "impeccable-engine $impeccable_version"
      test -f "$skills_root/browser-automation/references/safety.md"
      test -f "$skills_root/browser-automation/agents/openai.yaml"
      for reference in codeql semgrep sarif-parsing; do
        test -s "$skills_root/static-analysis/references/$reference/SKILL.md"
      done

      CODEX_SKILLS_TEST_ROOT="$skills_root" node --input-type=module <<'JS'
      import assert from 'node:assert/strict';

      const { renderPage } = await import(process.env.CODEX_SKILLS_TEST_ROOT + '/visual-explainer/kit/render.mjs');
      const result = renderPage('<!doctype html><html data-register="instrument"><head><link rel="stylesheet" href="kit.css" data-ve-kit></head><body><main><figure><figcaption>Skill packaging check</figcaption></figure></main></body></html>');
      assert.deepEqual(result.errors, []);
      assert.equal(result.kit, true);
      assert.match(result.html, /<style/);
      JS

      pinchtab_seed="$(sed -n 's|^[[:space:]]*cp \(/nix/store/[^ ]*pinchtab-config.json\) .*|\1|p' ${desktopPinchtabConfigActivationFile})"
      test -n "$pinchtab_seed"
      PINCHTAB_CONFIG="$pinchtab_seed" "${desktopPinchtabPackage}/bin/pinchtab" config validate

      touch "$out"
    '';
}
