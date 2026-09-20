{ctx}: let
  inherit (ctx) desktopCodexSkillsRoot desktopHome desktopPinchtabConfigActivationFile pkgs;
  expectedSkills = [
    "browser-automation"
    "caveman"
    "caveman-commit"
    "caveman-review"
    "code-review"
    "codebase-design"
    "diagnose"
    "domain-modeling"
    "grilling"
    "impeccable"
    "jev-mcp"
    "prototype"
    "static-analysis"
    "tdd"
    "technical-debt"
    "typesafe-ai"
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
          if name == "jev-mcp":
              policy_file = skill_dir / "agents/openai.yaml"
              if not policy_file.is_file() or "allow_implicit_invocation: false" not in policy_file.read_text(encoding="utf-8"):
                  raise SystemExit("jev-mcp must remain explicit-only")
      PY

      test -x "$skills_root/impeccable/scripts/impeccable"
      test -f "$skills_root/impeccable/reference/generate.md"
      test -f "$skills_root/browser-automation/references/safety.md"
      test -f "$skills_root/browser-automation/agents/openai.yaml"

      pinchtab_seed="$(sed -n 's|^[[:space:]]*cp \(/nix/store/[^ ]*pinchtab-config.json\) .*|\1|p' ${desktopPinchtabConfigActivationFile})"
      test -n "$pinchtab_seed"
      PINCHTAB_CONFIG="$pinchtab_seed" "${desktopHome}/bin/pinchtab" config validate

      mock_doctor="$TMPDIR/jev-mock-doctor.json"
      HOME="$TMPDIR/home" JEV_MCP_MOCK=1 "${desktopHome}/bin/jev-mcp" doctor --json >"$mock_doctor"
      python3 - "$mock_doctor" <<'PY'
      import json
      import sys

      report = json.load(open(sys.argv[1], encoding="utf-8"))
      if not report.get("ready") or report.get("model") != "jev-1.13" or not report.get("mock"):
          raise SystemExit(f"Jev mock doctor failed: {report}")
      PY

      if HOME="$TMPDIR/no-key-home" "${desktopHome}/bin/jev-mcp" doctor --json >"$TMPDIR/jev-no-key.json" 2>/dev/null; then
        echo "Jev doctor unexpectedly accepted a missing API key." >&2
        exit 1
      fi
      grep -q 'CONFIG_ERROR' "$TMPDIR/jev-no-key.json"

      XDG_STATE_HOME="$TMPDIR/state" "${desktopHome}/bin/jev-shadow-route" \
        --task-kind research --proposed-tier reasoning --effort high \
        --probability 0.82 --latency-ms 180 --usage-tokens 120
      python3 - "$TMPDIR/state/codex-jev/shadow.jsonl" <<'PY'
      import json
      import sys

      entry = json.loads(open(sys.argv[1], encoding="utf-8").readline())
      allowed = {"timestamp", "task_kind", "proposed_tier", "effort", "probability", "latency_ms", "usage_tokens", "estimated_cost_usd"}
      if not set(entry).issubset(allowed) or "task_kind" not in entry:
          raise SystemExit(f"Unsafe Jev shadow log entry: {entry}")
      PY

      touch "$out"
    '';
}
