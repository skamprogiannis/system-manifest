{ctx}: let
  inherit (ctx) desktopPinchtabPackage desktopCodexSkillsRoot desktopPinchtabConfigActivationFile pkgs;
  inherit (ctx) desktopModernWebGuidancePackage desktopAntigravityModernWebGuidance;
  expectedSkills = [
    "browser-automation"
    "code-review"
    "codebase-design"
    "diagnose"
    "domain-modeling"
    "grilling"
    "impeccable"
    "modern-web-guidance"
    "prototype"
    "socratic-tutor"
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
        pkgs.git
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

      package="${desktopModernWebGuidancePackage}"
      cli="$package/bin/modern-web-guidance"
      entrypoint="$package/lib/modern-web-guidance/skills/modern-web-guidance/modern-web.mjs"
      test "$(readlink "$skills_root/modern-web-guidance")" = "${desktopAntigravityModernWebGuidance}"
      grep -F "$cli search" "$skills_root/modern-web-guidance/SKILL.md"

      export HOME="$PWD/test-home" XDG_CONFIG_HOME="$PWD/test-home/.config"
      mkdir -p "$HOME" scan-fixture
      cd scan-fixture
      git init -q
      echo 'document.querySelectorAll(".example");' > index.js

      cat > "$PWD/tripwire.cjs" <<'JS'
      const assert = require('node:assert/strict');
      const childProcess = require('node:child_process');
      const { syncBuiltinESMExports } = require('node:module');
      const { promisify } = require('node:util');
      const fail = () => process.exit(97);

      globalThis.fetch = fail;
      for (const name of ['node:http', 'node:https']) {
        const module = require(name);
        module.get = module.request = fail;
      }
      for (const method of ['exec', 'execSync', 'execFileSync', 'spawn', 'spawnSync', 'fork']) {
        childProcess[method] = fail;
      }
      const execFile = childProcess.execFile;
      childProcess.execFile = (file, args, ...rest) => {
        if (process.env.TEST_LEGACY_SCAN !== '1' || file !== 'git' || args[0] !== 'ls-files') fail();
        return execFile(file, args, ...rest);
      };
      childProcess.execFile[promisify.custom] = (file, args, ...rest) => {
        if (process.env.TEST_LEGACY_SCAN !== '1' || file !== 'git' || args[0] !== 'ls-files') fail();
        return promisify(execFile)(file, args, ...rest);
      };
      syncBuiltinESMExports();
      process.on('exit', () => {
        assert.equal(process.env.DISABLE_TELEMETRY, '1');
        assert.equal(process.env.ENABLE_FILE_LOGGING, 'false');
      });
      JS

      export NODE_OPTIONS="--require=$PWD/tripwire.cjs"
      export DISABLE_TELEMETRY=0 ENABLE_FILE_LOGGING=true
      test "$("$cli" --version)" = "${desktopModernWebGuidancePackage.version}"
      "$cli" search "animate dialog backdrop" > search.json
      "$cli" list > list.json
      node "$entrypoint" retrieve animate-to-from-top-layer > guide.md
      TEST_LEGACY_SCAN=1 "$cli" legacy-scan . --json > scan.json
      for command in install update uninstall set-baseline set-allow-origin-trials set-allow-volatile-features; do
        status=0
        node "$entrypoint" "$command" > rejected.log 2>&1 || status=$?
        test "$status" -eq 1
        grep -F "Unknown command: $command" rejected.log
      done
      unset NODE_OPTIONS
      test ! -e modern-web.log
      test ! -e .mwgrc
      grep -F 'Guide for animate-to-from-top-layer' guide.md
      python3 - <<'PY'
      import json
      from pathlib import Path

      assert json.loads(Path("search.json").read_text())
      assert json.loads(Path("list.json").read_text())
      assert isinstance(json.loads(Path("scan.json").read_text()), dict)
      PY

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
