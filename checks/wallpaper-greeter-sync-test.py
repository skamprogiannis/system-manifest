"""Greeter receives complete immutable wallpaper snapshots, including after login."""
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import subprocess
import sys
from unittest import mock
import unittest

SOURCE = Path(os.environ.get('WALLPAPER_GREETER_SYNC_SOURCE', Path(__file__).parents[1]/'modules/system/wallpaper-greeter-sync.py'))
spec = importlib.util.spec_from_file_location('wallpaper_greeter_sync', SOURCE)
publisher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(publisher)


class GreeterSyncTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.source = self.root/'home/state/wallpaper-sync'
        self.source.mkdir(parents=True)
        self.destination = self.root/'greeter'
        self.destination.mkdir()
        (self.destination/'session.json').write_text('{"wallpaperPath":"stale.png"}')
        (self.destination/'colors.json').write_text('{}')
        (self.destination/'settings.json').write_text('{"keep":true}')
        self.current = self.source/'current'
        self.generation('first')

    def generation(self, name, color='#ffb596', light=False):
        directory = self.source/('generation-'+name)
        directory.mkdir()
        (directory/'wallpaper.png').write_bytes(publisher.PNG_HEADER+name.encode())
        session = dict.fromkeys(publisher.WALLPAPER_KEYS, str(directory/'wallpaper.png'))
        session.update(isLightMode=light, unrelated='preserved')
        (directory/'session.json').write_text(json.dumps(session))
        palette = {'mode': 'light' if light else 'dark', 'colors': {'dark': {'primary': color}, 'light': {'primary': '#825400'}}}
        (directory/'dms-colors.json').write_text(json.dumps(palette))
        self.current.unlink(missing_ok=True)
        self.current.symlink_to(directory.name)
        return directory

    def publish(self):
        return publisher.publish(self.current, self.destination)

    def test_replaces_stale_state_with_independent_greeter_copy(self):
        self.assertTrue(self.publish())
        session = json.loads((self.destination/'session.json').read_text())
        copied = Path(session['wallpaperPath'])
        self.assertEqual(copied.read_bytes(), publisher.PNG_HEADER+b'first')
        self.assertTrue(copied.is_relative_to(self.destination))
        self.assertEqual(session['unrelated'], 'preserved')
        self.assertEqual(json.loads((self.destination/'settings.json').read_text()), {'keep': True})
        for key in publisher.WALLPAPER_KEYS:
            self.assertEqual(session[key], str(copied))
        self.assertEqual(copied.stat().st_mode & 0o777, 0o644)
        self.assertEqual(copied.stat().st_uid, os.getuid())
        (self.current/'wallpaper.png').unlink()
        self.assertEqual(copied.read_bytes(), publisher.PNG_HEADER+b'first')

    def test_new_apply_updates_existing_greeter_without_restarting_it(self):
        self.publish()
        old = (self.destination/'wallpaper-current').resolve()
        self.generation('second', '#aabbcc')
        self.assertTrue(self.publish())
        self.assertNotEqual(old, (self.destination/'wallpaper-current').resolve())
        self.assertTrue(old.is_dir())
        palette = json.loads((self.destination/'colors.json').read_text())
        self.assertEqual(palette['colors']['dark']['primary'], '#aabbcc')

    def test_unchanged_or_preview_only_does_not_republish(self):
        self.publish()
        before = (self.destination/'wallpaper-current').lstat().st_mtime_ns
        (self.root/'preview-colors.json').write_text('{"primary":"#000000"}')
        self.assertFalse(self.publish())
        self.assertEqual(before, (self.destination/'wallpaper-current').lstat().st_mtime_ns)

    def test_light_mode_snapshot_is_published(self):
        self.publish()
        self.generation('light', light=True)
        self.publish()
        self.assertTrue(json.loads((self.destination/'session.json').read_text())['isLightMode'])
        self.assertEqual(json.loads((self.destination/'colors.json').read_text())['mode'], 'light')

    def test_invalid_source_preserves_last_complete_generation(self):
        self.publish()
        old = (self.destination/'wallpaper-current').resolve()
        directory = self.generation('bad')
        (directory/'dms-colors.json').write_text('{broken')
        with self.assertRaises((ValueError, publisher.PublishError)):
            self.publish()
        self.assertEqual((self.destination/'wallpaper-current').resolve(), old)
        self.assertEqual(Path(json.loads((self.destination/'session.json').read_text())['wallpaperPath']).read_bytes(), publisher.PNG_HEADER+b'first')

    def test_user_symlink_cannot_copy_root_readable_file(self):
        self.publish()
        old = (self.destination/'wallpaper-current').resolve()
        directory = self.generation('symlink')
        (directory/'wallpaper.png').unlink()
        (directory/'wallpaper.png').symlink_to(self.root/'sensitive')
        (self.root/'sensitive').write_text('not wallpaper')
        with self.assertRaises((OSError, publisher.PublishError)):
            self.publish()
        self.assertEqual((self.destination/'wallpaper-current').resolve(), old)

    def test_source_current_outside_snapshot_root_is_rejected(self):
        self.current.unlink()
        self.current.symlink_to(self.destination)
        with self.assertRaises(publisher.PublishError):
            self.publish()


    def test_source_pointer_change_cannot_mix_snapshot_files(self):
        original = publisher.read_regular
        changed = False
        def move_pointer(directory_fd, name, owner, limit):
            nonlocal changed
            if not changed:
                changed = True
                self.generation('racing', '#aabbcc')
            return original(directory_fd, name, owner, limit)
        with mock.patch.object(publisher, 'read_regular', side_effect=move_pointer):
            self.publish()
        session = json.loads((self.destination/'session.json').read_text())
        self.assertEqual(Path(session['wallpaperPath']).read_bytes(), publisher.PNG_HEADER+b'first')
        self.assertEqual(json.loads((self.destination/'colors.json').read_text())['colors']['dark']['primary'], '#ffb596')

    def test_copy_failure_keeps_previous_generation(self):
        self.publish()
        previous = (self.destination/'wallpaper-current').resolve()
        self.generation('write-failure')
        original = publisher.write_file
        def fail_colors(path, data):
            if path.name == 'colors.json':
                raise OSError('fixture full disk')
            original(path, data)
        with mock.patch.object(publisher, 'write_file', side_effect=fail_colors):
            with self.assertRaises(OSError):
                self.publish()
        self.assertEqual((self.destination/'wallpaper-current').resolve(), previous)

    def test_missing_first_boot_snapshot_does_not_block_login(self):
        self.current.unlink()
        result = subprocess.run([sys.executable, str(SOURCE), str(self.current), str(self.destination)],
                                text=True, capture_output=True, check=False, timeout=2)
        self.assertEqual(result.returncode, 0)
        self.assertIn('snapshot retained', result.stderr)

    def test_broken_stable_links_are_repaired(self):
        self.publish()
        (self.destination/'colors.json').unlink()
        (self.destination/'colors.json').write_text('{}')
        self.assertTrue(self.publish())
        self.assertTrue((self.destination/'colors.json').is_symlink())
        self.assertEqual(json.loads((self.destination/'colors.json').read_text())['colors']['dark']['primary'], '#ffb596')


if __name__ == '__main__':
    unittest.main()
