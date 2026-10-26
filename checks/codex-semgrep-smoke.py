"""Verify the installed Semgrep frontend can execute its native scan engine."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

with tempfile.TemporaryDirectory(prefix="semgrep-smoke-") as temporary:
    root = Path(temporary)
    (root / "rule.yaml").write_text("""rules:
- id: system-refresh-probe
  languages: [python]
  severity: WARNING
  message: Local test finding
  pattern: eval($X)
""")
    (root / "positive.py").write_text('eval("1 + 1")\n')
    (root / "clean.py").write_text('print("hello")\n')
    env = {key: value for key, value in os.environ.items() if key in {"PATH", "LANG", "SSL_CERT_FILE"}}
    env.update({"HOME": str(root), "SEMGREP_SETTINGS_FILE": str(root / "settings.yml"),
                "SEMGREP_ENABLE_VERSION_CHECK": "0", "SEMGREP_SEND_METRICS": "off"})
    result = subprocess.run(
        [sys.argv[1], "scan", "--config", "rule.yaml", "--json", "--metrics=off",
         "--disable-version-check", "--jobs=1", "positive.py", "clean.py"],
        cwd=root, env=env, capture_output=True, text=True, timeout=60,
    )
    assert result.returncode == 0, result.stderr
    report = json.loads(result.stdout)
    assert not report["errors"], report["errors"]
    assert len(report["results"]) == 1, report["results"]
    finding = report["results"][0]
    assert finding["check_id"] == "system-refresh-probe", finding
    assert finding["path"] == "positive.py", finding
    assert {Path(path).name for path in report["paths"]["scanned"]} == {"positive.py", "clean.py"}, report["paths"]
    print("Installed Semgrep scanned positive/clean fixtures with one expected finding")
