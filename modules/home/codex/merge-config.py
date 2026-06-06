from pathlib import Path
import copy
import datetime
import os
import sys
import tempfile
import tomllib

import tomli_w


def merge(seed_value, current_value, path=()):
    if not isinstance(seed_value, dict) or not isinstance(current_value, dict):
        return copy.deepcopy(seed_value)

    merged = copy.deepcopy(seed_value)
    for key, value in current_value.items():
        next_path = path + (key,)
        if next_path == ("projects",) and isinstance(value, dict):
            projects = copy.deepcopy(value)
            projects.update(seed_value.get(key, {}))
            merged[key] = projects
        elif key not in merged:
            merged[key] = copy.deepcopy(value)
        elif isinstance(merged[key], dict) and isinstance(value, dict):
            merged[key] = merge(merged[key], value, next_path)
    return merged


def load_current_config(config_path):
    if not (config_path.exists() or config_path.is_symlink()):
        return {}

    try:
        with config_path.open("rb") as f:
            return tomllib.load(f)
    except tomllib.TOMLDecodeError:
        stamp = datetime.datetime.now(datetime.UTC).strftime("%Y%m%d%H%M%S")
        backup_path = config_path.with_name(f"{config_path.name}.invalid-{stamp}")
        backup_path.write_bytes(config_path.read_bytes())
        return {}


def atomic_write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(
        prefix=f".{path.name}.",
        suffix=".tmp",
        dir=path.parent,
        text=True,
    )
    try:
        with os.fdopen(fd, "w") as tmp:
            tmp.write(text)
        os.chmod(tmp_name, 0o600)
        os.replace(tmp_name, path)
    finally:
        if os.path.exists(tmp_name):
            os.unlink(tmp_name)


def main():
    if len(sys.argv) != 3:
        print("usage: merge-config.py SEED_CONFIG TARGET_CONFIG", file=sys.stderr)
        return 2

    seed_path = Path(sys.argv[1])
    config_path = Path(sys.argv[2])

    with seed_path.open("rb") as f:
        seed = tomllib.load(f)

    merged = merge(seed, load_current_config(config_path))
    atomic_write(config_path, tomli_w.dumps(merged))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
