"""Merge only our pinned hook handlers; preserve unrelated user hooks."""

import copy
import json
from pathlib import Path
import re
import sys
import tempfile
import os

OWN_COMMAND = re.compile(r"^/nix/store/[a-z0-9]{32}-codex-clef/bin/codex-clef hook$")


def merge(seed, current):
    if not isinstance(current, dict) or not isinstance(current.get("hooks", {}), dict):
        raise ValueError("invalid existing hooks configuration")
    merged = copy.deepcopy(current)
    hooks = merged.setdefault("hooks", {})
    for event, groups in list(hooks.items()):
        if not isinstance(groups, list):
            raise ValueError("invalid existing hook groups")
        retained = []
        for group in groups:
            handlers = group.get("hooks") if isinstance(group, dict) else None
            if not isinstance(handlers, list) or not all(
                isinstance(h, dict) for h in handlers
            ):
                raise ValueError("invalid existing hook handlers")
            group["hooks"] = [
                handler
                for handler in handlers
                if not OWN_COMMAND.fullmatch(handler.get("command", ""))
            ]
            if group["hooks"]:
                retained.append(group)
        hooks[event] = retained
    for event, groups in seed["hooks"].items():
        hooks.setdefault(event, []).extend(copy.deepcopy(groups))
    return merged


def main():
    seed, target = map(Path, sys.argv[1:])
    current = json.loads(target.read_text()) if target.exists() else {}
    result = merge(json.loads(seed.read_text()), current)
    target.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=".hooks-", dir=target.parent)
    try:
        with os.fdopen(fd, "w") as handle:
            json.dump(result, handle, indent=2)
            handle.write("\n")
        os.replace(temporary, target)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


if __name__ == "__main__":
    main()
