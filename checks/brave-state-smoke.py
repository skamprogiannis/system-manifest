import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile


helper = sys.argv[1]
with tempfile.TemporaryDirectory(prefix="brave-state-") as temporary_home:
    home = Path(temporary_home)
    profile = home / ".config/BraveSoftware/Brave-Browser"
    preferences = profile / "Default/Preferences"
    local_state = profile / "Local State"
    preferences.parent.mkdir(parents=True)
    preferences.write_text(json.dumps({
        "profile": {"exit_type": "Crashed", "exited_cleanly": False, "custom": "keep"},
        "brave": {"tabs": {"custom": [1, 2]}},
        "unrelated": {"keep": True},
    }))
    local_state.write_text(json.dumps({
        "brave": {"p3a": {"custom": "keep"}},
        "unrelated": ["keep"],
    }))
    extension = profile / "Default/Local Extension Settings/hfjbmagddngcpeloejdejnfgbamkjaeg/stale"
    extension.parent.mkdir(parents=True)
    extension.write_text("unchanged while running")
    original_files = {path: path.read_bytes() for path in [preferences, local_state, extension]}
    environment = dict(os.environ, HOME=str(home))

    for process_name in ["brave", "brave-browser"]:
        # A real named process exercises the helper's absolute-path pgrep guard.
        browser = subprocess.Popen(
            [sys.executable, "-c", """
import ctypes, sys, time
assert ctypes.CDLL(None).prctl(15, sys.argv[1].encode(), 0, 0, 0) == 0
print("ready", flush=True)
time.sleep(60)
""", process_name],
            stdout=subprocess.PIPE,
            text=True,
        )
        try:
            assert browser.stdout.readline().strip() == "ready"
            result = subprocess.run([helper], env=environment, capture_output=True, text=True, timeout=10)
            assert result.returncode == 1, result
            assert "Brave is running" in result.stderr, result.stderr
            for path, content in original_files.items():
                assert path.read_bytes() == content, f"Modified {path} while {process_name} was running"
        finally:
            browser.terminate()
            browser.wait(timeout=5)
            browser.stdout.close()

    result = subprocess.run([helper], env=environment, capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, result.stderr
    updated = json.loads(preferences.read_text())
    assert updated["profile"]["exit_type"] == "Normal"
    assert updated["profile"]["exited_cleanly"] is True
    assert updated["profile"]["custom"] == "keep"
    assert updated["session"]["restore_on_startup"] == 1
    assert updated["brave"]["tabs"]["vertical_tabs_enabled"] is True
    assert updated["brave"]["tabs"]["vertical_tabs_on_right"] is True
    assert updated["brave"]["tabs"]["custom"] == [1, 2]
    assert updated["unrelated"] == {"keep": True}
    updated_state = json.loads(local_state.read_text())
    assert updated_state["brave"]["p3a"]["enabled"] is False
    assert updated_state["brave"]["p3a"]["custom"] == "keep"
    assert updated_state["unrelated"] == ["keep"]
    assert not extension.exists(), "Vimium C state was not reseeded"
    print("Brave state smoke checks passed")
