#!/usr/bin/env python3
"""Read installed Steam titles without consulting account metadata or the network."""

import json
import os
from pathlib import Path
import re

import vdf


def default_roots(home=None, environ=None):
    """Return this user's Steam roots, respecting an absolute XDG_DATA_HOME."""
    home = Path.home() if home is None else Path(home)
    environ = os.environ if environ is None else environ
    data = Path(environ.get("XDG_DATA_HOME") or home / ".local/share")
    if not data.is_absolute():
        data = home / ".local/share"
    return [data / "Steam", home / ".steam/steam"]


def _read_vdf(path):
    try:
        with path.open(encoding="utf-8") as source:
            return vdf.load(source, escaped=True)
    except (OSError, UnicodeError, SyntaxError, ValueError):
        return {}


def _unique_paths(paths):
    seen = set()
    for path in paths:
        try:
            canonical = Path(path).resolve()
        except (OSError, RuntimeError):
            continue
        if canonical not in seen:
            seen.add(canonical)
            yield canonical


def library_roots(roots):
    """Find distinct libraries declared by the supplied Steam installations."""
    roots = list(_unique_paths(roots))
    libraries = list(roots)
    for root in roots:
        folders = _read_vdf(root / "steamapps/libraryfolders.vdf").get("libraryfolders", {})
        if not isinstance(folders, dict):
            continue
        for index, entry in folders.items():
            if not re.fullmatch(r"[0-9]+", index):
                continue
            # Older Steam versions stored the library path directly.
            path = entry.get("path") if isinstance(entry, dict) else entry
            if isinstance(path, str) and path and Path(path).is_absolute():
                libraries.append(Path(path))
    return list(_unique_paths(libraries))


def collect_titles(roots=None):
    """Return {steam_app_ID: title}; malformed or unavailable files are skipped."""
    titles = {}
    for library in library_roots(default_roots() if roots is None else roots):
        try:
            manifests = sorted((library / "steamapps").glob("appmanifest_*.acf"))
        except OSError:
            continue
        for manifest in manifests:
            state = _read_vdf(manifest).get("AppState", {})
            if not isinstance(state, dict):
                continue
            appid, name = state.get("appid"), state.get("name")
            if not isinstance(appid, str) or not re.fullmatch(r"[0-9]+", appid):
                continue
            # Match the manifest identity and leave Steam's appid-zero alias alone.
            appid = appid.lstrip("0")
            if not appid or manifest.name != f"appmanifest_{appid}.acf":
                continue
            if not isinstance(name, str) or not name.strip():
                continue
            titles.setdefault(f"steam_app_{appid}", name)
    return titles


if __name__ == "__main__":
    print(json.dumps(collect_titles(), ensure_ascii=False, sort_keys=True))
