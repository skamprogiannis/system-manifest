{ctx}: let
  inherit (ctx) pkgs registry;
  registryJson = builtins.toFile "check-registry.json" (builtins.toJSON registry);
in {
  ci-registry =
    pkgs.runCommand "ci-registry-check" {
      nativeBuildInputs = [pkgs.python3];
    } ''
      set -euo pipefail

      python3 - ${registryJson} ${../.github/workflows/validate.yml} <<'PY'
      import json
      import re
      import sys
      from pathlib import Path

      registry = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
      workflow = Path(sys.argv[2]).read_text(encoding="utf-8").splitlines()

      def parse_matrix(job_name, key):
          in_job = False
          in_key = False
          values = []
          job_indent = None
          key_indent = None

          for line in workflow:
              if re.match(r"^  [A-Za-z0-9_-]+:", line):
                  current = line.strip()[:-1]
                  in_job = current == job_name
                  in_key = False
                  job_indent = 2 if in_job else None
                  continue

              if not in_job:
                  continue

              if job_indent is not None and line and not line.startswith(" " * (job_indent + 2)):
                  in_key = False

              key_match = re.match(r"^(?P<indent>\s+)" + re.escape(key) + r":\s*$", line)
              if key_match:
                  in_key = True
                  key_indent = len(key_match.group("indent"))
                  continue

              if in_key:
                  item = re.match(r"^(?P<indent>\s+)-\s+(?P<value>[A-Za-z0-9_-]+)\s*$", line)
                  if item and len(item.group("indent")) > key_indent:
                      values.append(item.group("value"))
                      continue

                  if line.strip() and len(line) - len(line.lstrip(" ")) <= key_indent:
                      in_key = False

          if not values:
              raise SystemExit(f"Could not find matrix {job_name}.{key} in workflow")

          return values

      checks = {
          "host": parse_matrix("host-check", "host"),
          "support": parse_matrix("support-check", "check"),
      }

      failures = []
      for group in ("host", "support"):
          expected = registry[group]
          actual = checks[group]
          if actual != expected:
              failures.append(
                  f"{group} matrix drift:\n"
                  f"  expected: {expected}\n"
                  f"  actual:   {actual}"
              )

      if failures:
          print("\n\n".join(failures), file=sys.stderr)
          raise SystemExit(1)
      PY

      touch "$out"
    '';
}
