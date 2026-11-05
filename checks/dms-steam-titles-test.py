#!/usr/bin/env python3
"""Fixture-only checks for the installed Steam title lookup."""

import importlib.util
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

import vdf


helper = Path(sys.argv.pop(1)) if len(sys.argv) > 1 and not sys.argv[1].startswith("-") else (
    Path(__file__).resolve().parents[1] / "modules/home/dms/steam-titles.py"
)
spec = importlib.util.spec_from_file_location("steam_titles", helper)
steam_titles = importlib.util.module_from_spec(spec)
spec.loader.exec_module(steam_titles)


class SteamTitlesTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.home = Path(self.temporary.name)
        self.root = self.home / "Steam"

    def write(self, path, text):
        path.parent.mkdir(parents=True, exist_ok=True)
        if isinstance(text, dict):
            text = vdf.dumps(text, pretty=True, escaped=True)
        path.write_text(text, encoding="utf-8")

    def manifest(self, root, appid, body):
        self.write(root / f"steamapps/appmanifest_{appid}.acf", body)

    def test_multiple_libraries_and_escaped_titles(self):
        library = self.home / "Games on disk"
        old_library = self.home / "Old Library"
        self.write(self.root / "steamapps/libraryfolders.vdf", {"libraryfolders": {
            "0": {"path": str(self.root)}, "1": {"path": str(library)},
            "2": str(old_library),
        }})
        self.manifest(self.root, 10, {"AppState": {"appid": "10", "name": "First game"}})
        self.manifest(library, 20, r'''"AppState"
{
    "appid" "20"
    "name" "A \"quoted\" game \\ edition"
}
''')
        self.manifest(old_library, 30, {"AppState": {"appid": "30", "name": "Ελληνικά"}})
        self.assertEqual(steam_titles.collect_titles([self.root]), {
            "steam_app_10": "First game",
            "steam_app_20": 'A "quoted" game \\ edition',
            "steam_app_30": "Ελληνικά",
        })

    def test_bad_files_do_not_discard_valid_metadata(self):
        self.write(self.root / "steamapps/libraryfolders.vdf", '"libraryfolders"\n{\n')
        self.manifest(self.root, 10, {"AppState": {"appid": "10", "name": "Survivor"}})
        self.manifest(self.root, 20, '"AppState"\n{\n"appid" "20"\n')
        self.manifest(self.root, 30, '"AppState" "wrong shape"')
        self.manifest(self.root, 40, {"AppState": {"appid": "40", "name": {"bad": "shape"}}})
        (self.root / "steamapps/appmanifest_50.acf").write_bytes(b"\xff")
        self.assertEqual(steam_titles.collect_titles([self.home / "missing", self.root]), {
            "steam_app_10": "Survivor",
        })

    def test_unavailable_manifest_is_skipped(self):
        self.manifest(self.root, 10, {"AppState": {"appid": "10", "name": "Available"}})
        self.manifest(self.root, 20, {"AppState": {"appid": "20", "name": "Unavailable"}})
        original_open = Path.open

        def open_fixture(path, *args, **kwargs):
            if path.name == "appmanifest_20.acf":
                raise PermissionError("fixture")
            return original_open(path, *args, **kwargs)

        with patch.object(Path, "open", open_fixture):
            self.assertEqual(steam_titles.collect_titles([self.root]), {"steam_app_10": "Available"})

    def test_invalid_id_and_name_are_ignored(self):
        for filename, appid, name in [
            (0, "0", "Steam"), (10, "-10", "Negative"),
            (20, "abc", "Invalid"), (30, "31", "Mismatch"),
            (40, "40", "   "), (50, "50", ""),
            (60, "６０", "Non-ASCII ID"), (70, "70", {"bad": "shape"}),
        ]:
            self.manifest(self.root, filename, {"AppState": {"appid": appid, "name": name}})
        self.assertEqual(steam_titles.collect_titles([self.root]), {})

    def test_duplicate_roots_and_library_aliases(self):
        self.root.mkdir()
        alias = self.home / "alias"
        alias.symlink_to(self.root, target_is_directory=True)
        self.write(self.root / "steamapps/libraryfolders.vdf", {"libraryfolders": {
            "0": {"path": str(alias)}, "1": {"path": {"bad": "shape"}},
            "2": "relative/path",
        }})
        self.assertEqual(steam_titles.library_roots([self.root, alias, self.root]), [self.root])

    def test_missing_and_invalid_library_lists(self):
        self.assertEqual(steam_titles.collect_titles([self.root]), {})
        self.write(self.root / "steamapps/libraryfolders.vdf", '"libraryfolders" "bad"')
        self.assertEqual(steam_titles.library_roots([self.root]), [self.root])

    def test_default_roots_respect_xdg_and_home(self):
        self.assertEqual(steam_titles.default_roots(self.home, {}), [
            self.home / ".local/share/Steam", self.home / ".steam/steam",
        ])
        self.assertEqual(steam_titles.default_roots(self.home, {"XDG_DATA_HOME": str(self.home / "data")})[0], self.home / "data/Steam")
        for value in ("", "relative"):
            self.assertEqual(steam_titles.default_roots(self.home, {"XDG_DATA_HOME": value})[0], self.home / ".local/share/Steam")


if __name__ == "__main__":
    unittest.main()
