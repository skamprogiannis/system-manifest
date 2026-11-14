import json
import os
from pathlib import Path
import sys
import tempfile


def main():
    if len(sys.argv) != 3:
        sys.exit("usage: merge-mcp.py SEED_CONFIG TARGET_CONFIG")

    seed_path = Path(sys.argv[1])
    target_path = Path(sys.argv[2])

    with seed_path.open("r", encoding="utf-8") as f:
        seed = json.load(f)

    current = {}
    if target_path.exists() and target_path.stat().st_size > 0:
        try:
            with target_path.open("r", encoding="utf-8") as f:
                current = json.load(f)
        except json.JSONDecodeError:
            current = {}

    merged_servers = current.get("mcpServers", {})
    seed_servers = seed.get("mcpServers", {})

    # Check for Linear API key in ~/.config/linear/api-key or LINEAR_API_KEY env
    linear_key = os.environ.get("LINEAR_API_KEY", "").strip()
    key_file = Path.home() / ".config" / "linear" / "api-key"
    if not linear_key and key_file.is_file():
        linear_key = key_file.read_text(encoding="utf-8").strip()

    for name, s_cfg in seed_servers.items():
        if name not in merged_servers:
            merged_servers[name] = s_cfg.copy()
        else:
            cur_server = merged_servers[name]
            for key in ("command", "args", "env", "url", "serverUrl"):
                if key in s_cfg:
                    cur_server[key] = s_cfg[key]

    # Inject Linear Bearer token into linear server if key exists and no custom auth is set
    if linear_key and "linear" in merged_servers:
        headers = merged_servers["linear"].setdefault("headers", {})
        if "Authorization" not in headers:
            headers["Authorization"] = f"Bearer {linear_key}"

    target_path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_path_str = tempfile.mkstemp(
        prefix=f".{target_path.name}.",
        suffix=".tmp",
        dir=target_path.parent,
        text=True,
    )
    tmp_path = Path(tmp_path_str)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as tmp:
            json.dump({"mcpServers": merged_servers}, tmp, indent=2)
            tmp.write("\n")
        os.chmod(tmp_path, 0o600)
        os.replace(tmp_path, target_path)
    finally:
        if tmp_path.exists():
            tmp_path.unlink()


if __name__ == "__main__":
    main()
