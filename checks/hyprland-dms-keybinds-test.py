"""Check DMS reads declarative Home Manager Lua without modifying it."""

import json
from pathlib import Path
import subprocess
import sys
import tempfile


def read_binds(dms, config):
    with tempfile.TemporaryDirectory(prefix="dms-keybinds-") as directory:
        root = Path(directory)
        path = root / "hyprland.lua"
        path.write_text(config)
        before = path.read_bytes()
        result = subprocess.run(
            [dms, "keybinds", "show", "hyprland", "--path", directory],
            check=True, capture_output=True, text=True,
        )
        assert path.read_bytes() == before, "DMS rewrote declarative bindings"
        assert sorted(p.name for p in root.iterdir()) == ["hyprland.lua"], (
            "DMS created an additional binding file"
        )
        return [bind for group in json.loads(result.stdout)["binds"].values() for bind in group]


def assert_binding(binds, key, action):
    matching = [b for b in binds if b["key"].lower() == key.lower()]
    assert len(matching) == 1, f"Expected one {key} binding, got {matching}"
    assert matching[0]["action"] == action, matching[0]
    assert matching[0]["source"] == "config", matching[0]


dms, *generated_paths = sys.argv[1:]
fixture = '''local mod = "SUPER"
hl.bind((mod .. " + d"), (hl.dsp.exec_cmd("dms ipc call spotlight toggle")))
'''
assert_binding(read_binds(dms, fixture), "SUPER+d", "exec dms ipc call spotlight toggle")
for generated_path in generated_paths:
    config = Path(generated_path).read_text()
    binds = read_binds(dms, config)
    for key, action in [
        ("SUPER+d", "exec dms ipc call spotlight toggle"),
        ("SUPER+n", "exec dms ipc call notepad toggle"),
        ("SUPER+y", "exec dms ipc call clipboard toggle"),
        ("SUPER+s", "exec dms ipc call settings toggle"),
        ("SUPER+SHIFT+w", "exec dms ipc call dash toggle wallpaper"),
        ("Print", "exec dms screenshot region --dir ~/pictures/screenshots"),
    ]:
        assert_binding(binds, key, action)
    declared = sum(line.lstrip().startswith("hl.bind(") for line in config.splitlines())
    assert len(binds) == declared, f"DMS found {len(binds)} of {declared} generated binds"
    print(f"{generated_path}: DMS recognized all {declared} declarative bindings, including Super+D")
