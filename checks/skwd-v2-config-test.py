"""Credential-free regressions for the v1 Steam settings migration."""
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

SOURCE = Path(os.environ.get('SKWD_V2_CONFIG_SOURCE', Path(__file__).parents[1] / 'modules/home/wallpaper/configure-v2.py'))
MANAGED = {'features': {'matugen': True}, 'theme': {'authority': 'skwd', 'engine': 'matugen', 'targets': ['dms']},
           'integrations': [{'name': 'system-manifest-dms-preview', 'template': 'new-template'}]}


class MigrationTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.home = Path(self.tmp.name)
        self.config = self.home / '.config/skwd-wall-v2/config.json'
        self.legacy = self.home / '.config/skwd-wall/config.json'
        self.secrets = self.legacy.with_name('secrets.env')
        self.managed = self.home / 'managed.json'
        self.write(self.managed, MANAGED)
        self.steam = self.home / '.local/share/Steam'
        self.steam.mkdir(parents=True)
        (self.home / '.steam').mkdir()
        (self.home / '.steam/root').symlink_to(self.steam, target_is_directory=True)
        self.library = self.home / 'games/SteamLibrary'
        self.workshop = self.library / 'steamapps/workshop/content/431960'
        self.assets = self.library / 'steamapps/common/wallpaper_engine/assets'
        self.workshop.mkdir(parents=True)
        self.assets.mkdir(parents=True)
        self.write(self.legacy, {'paths': {'steam': str(self.library), 'steamWorkshop': str(self.workshop), 'steamWeAssets': str(self.assets)},
                                 'steam': {'username': '', 'apiKey': ''}})
        self.vdf(self.library / 'steamapps/appmanifest_431960.acf', '"AppState" { "appid" "431960" "LastOwner" "12345" }')
        self.vdf(self.steam / 'config/loginusers.vdf', '"users" { "67890" { "AccountName" "wrong" } "12345" { "AccountName" "fixture-owner" } }')

    def write(self, path, data):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(data))

    def vdf(self, path, text):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)

    def run_migration(self):
        result = subprocess.run([sys.executable, str(SOURCE), '--home', str(self.home), '--managed-theme', str(self.managed)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result

    def load(self):
        return json.loads(self.config.read_text())

    def private(self, path):
        self.assertEqual(path.stat().st_mode & 0o777, 0o600)

    def test_recovers_library_and_exact_owner_preserving_ui_and_first_backup(self):
        original = {'paths': {'wallpaper': '~/wallpapers'}, 'steam': {'backend': 'steamcmd'}, 'columns': 6, 'rows': 3,
                    'integrations': [{'name': 'other'}, {'name': 'system-manifest-dms-preview', 'template': 'old'}]}
        self.write(self.config, original)
        self.secrets.write_text('STEAM_API_KEY="dummy-secret"\nWALLHAVEN_API_KEY="unrelated"\n')
        self.secrets.chmod(0o644)
        self.legacy.chmod(0o644)
        before = self.config.read_bytes()
        result = self.run_migration()
        data = self.load()
        self.assertEqual(data['paths']['steam'], str(self.steam))
        self.assertEqual(data['paths']['steamWorkshop'], str(self.workshop))
        self.assertEqual(data['paths']['steamWeAssets'], str(self.assets))
        self.assertEqual(data['steam'], {'backend': 'steamcmd', 'username': 'fixture-owner', 'apiKey': 'dummy-secret'})
        self.assertEqual((data['columns'], data['rows']), (6, 3))
        self.assertTrue(data['features']['steam'])
        self.assertEqual(data['integrations'], [{'name': 'other'}, MANAGED['integrations'][0]])
        backup = self.config.with_name('config.json.pre-steam-v2')
        self.assertEqual(backup.read_bytes(), before)
        for path in (backup, self.config, self.secrets, self.legacy):
            self.private(path)
        self.assertNotIn('dummy-secret', result.stdout + result.stderr)
        stat = self.config.stat()
        self.run_migration()
        self.assertEqual((self.config.stat().st_ino, self.config.stat().st_mtime_ns), (stat.st_ino, stat.st_mtime_ns))
        self.assertEqual(backup.read_bytes(), before)

    def test_existing_values_and_explicit_false_survive(self):
        self.write(self.config, {'paths': {'steam': '/chosen/root', 'steamWorkshop': '/chosen/workshop', 'steamWeAssets': '/chosen/assets'},
                                 'steam': {'backend': 'client', 'username': 'chosen', 'apiKey': 'chosen-secret'}, 'features': {'steam': False}})
        self.run_migration()
        data = self.load()
        self.assertEqual(data['paths']['steam'], '/chosen/root')
        self.assertEqual(data['steam'], {'backend': 'client', 'username': 'chosen', 'apiKey': 'chosen-secret'})
        self.assertFalse(data['features']['steam'])

    def test_null_and_empty_fields_filled_and_legacy_credentials_precede_metadata(self):
        old = json.loads(self.legacy.read_text())
        old['steam'] = {'username': 'legacy-owner', 'apiKey': 'legacy-secret'}
        self.write(self.legacy, old)
        self.write(self.config, {'paths': {'steamWorkshop': None, 'steamWeAssets': ''}, 'steam': {'username': '', 'apiKey': None, 'backend': ''}})
        self.secrets.write_text('STEAM_API_KEY=env-secret\n')
        self.run_migration()
        self.assertEqual(self.load()['steam'], {'username': 'legacy-owner', 'apiKey': 'legacy-secret', 'backend': 'steamcmd'})

    def test_dotenv_is_literal_and_never_executes_shell(self):
        marker = self.home / 'executed'
        literal = '$(touch ' + str(marker) + ')`id`$HOME'
        self.secrets.write_text('export STEAM_API_KEY="' + literal + '"\n')
        result = self.run_migration()
        self.assertEqual(self.load()['steam']['apiKey'], literal)
        self.assertFalse(marker.exists())
        self.assertNotIn(literal, result.stdout + result.stderr)

    def test_malformed_legacy_and_dotenv_keep_valid_v2_secret_and_hide_diagnostics(self):
        self.legacy.write_text('{"secret": "never-log-this", broken')
        self.secrets.write_text('STEAM_API_KEY="never-log-this\n')
        self.write(self.config, {'steam': {'apiKey': 'chosen-secret'}, 'paths': {'wallpaper': '/chosen'}})
        result = self.run_migration()
        self.assertEqual(self.load()['steam']['apiKey'], 'chosen-secret')
        self.assertEqual(self.load()['paths']['wallpaper'], '/chosen')
        self.assertNotIn('never-log-this', result.stdout + result.stderr)
        self.private(self.secrets)

    def test_malformed_nested_sections_do_not_crash(self):
        self.write(self.legacy, {'paths': ['bad'], 'steam': 'bad'})
        self.write(self.config, {'paths': ['keep'], 'steam': ['keep'], 'features': 'bad', 'integrations': 'bad'})
        self.run_migration()
        self.assertEqual(self.load()['paths'], ['keep'])
        self.assertEqual(self.load()['steam'], ['keep'])
        self.assertTrue(self.load()['features']['matugen'])

    def test_ambiguous_owner_and_malformed_vdf_do_not_guess(self):
        self.vdf(self.steam / 'steamapps/appmanifest_431960.acf', '"AppState" { "appid" "431960" "LastOwner" "67890" }')
        self.run_migration()
        self.assertNotIn('username', self.load()['steam'])
        self.config.unlink()
        (self.steam / 'steamapps/appmanifest_431960.acf').unlink()
        self.vdf(self.steam / 'config/loginusers.vdf', '"users" { "12345" { "AccountName" "private-value"')
        result = self.run_migration()
        self.assertNotIn('username', self.load()['steam'])
        self.assertNotIn('private-value', result.stderr)

    def test_invalid_v2_backup_private_and_preserved(self):
        self.config.parent.mkdir(parents=True)
        invalid = b'{"apiKey":"private-value",broken'
        self.config.write_bytes(invalid)
        self.config.chmod(0o644)
        result = self.run_migration()
        backup = self.config.with_name('config.json.invalid')
        self.assertEqual(backup.read_bytes(), invalid)
        self.private(backup)
        self.private(self.config)
        self.assertNotIn('private-value', result.stdout + result.stderr)
        self.run_migration()
        self.assertEqual(backup.read_bytes(), invalid)

    def test_backups_are_private_before_first_byte_and_never_overwritten(self):
        spec = importlib.util.spec_from_file_location('skwd_config', SOURCE)
        helper = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(helper)
        backup = self.home / 'private-backup'
        real_fdopen = os.fdopen
        observed_modes = []

        def check_mode(fd, *args, **kwargs):
            observed_modes.append(os.fstat(fd).st_mode & 0o777)
            return real_fdopen(fd, *args, **kwargs)

        with mock.patch.object(helper.os, 'fdopen', side_effect=check_mode):
            helper.private_backup(backup, b'fixture-secret')
        self.assertEqual(observed_modes, [0o600])
        backup.chmod(0o644)
        helper.private_backup(backup, b'new-fixture-secret')
        self.assertEqual(backup.read_bytes(), b'fixture-secret')
        self.private(backup)

    def test_failed_backup_is_removed_and_retry_preserves_complete_original(self):
        spec = importlib.util.spec_from_file_location('skwd_config', SOURCE)
        helper = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(helper)
        self.write(self.config, {'steam': {'apiKey': 'original-fixture-secret'}, 'columns': 6})
        original = self.config.read_bytes()
        backup = self.config.with_name('config.json.pre-steam-v2')
        real_fdopen = os.fdopen

        class BrokenWriter:
            def __init__(self, fd, *args, **kwargs):
                self.stream = real_fdopen(fd, *args, **kwargs)

            def __enter__(self):
                return self

            def __exit__(self, *args):
                self.stream.close()

            def fileno(self):
                return self.stream.fileno()

            def write(self, contents):
                self.stream.write(contents[:7])
                self.stream.flush()
                raise OSError('simulated disk full')

        with mock.patch.object(helper.os, 'fdopen', BrokenWriter), self.assertRaises(OSError):
            helper.configure(self.home, MANAGED)
        self.assertFalse(backup.exists())
        self.assertEqual(self.config.read_bytes(), original)
        with mock.patch.object(helper.os, 'fsync', side_effect=OSError('simulated sync failure')), self.assertRaises(OSError):
            helper.configure(self.home, MANAGED)
        self.assertFalse(backup.exists())
        self.assertEqual(self.config.read_bytes(), original)
        helper.configure(self.home, MANAGED)
        self.assertEqual(backup.read_bytes(), original)
        self.private(backup)
        helper.private_backup(backup, b'never-replace-first-backup')
        self.assertEqual(backup.read_bytes(), original)

    def test_unreadable_legacy_leaves_valid_v2_credential_and_generic_warning(self):
        spec = importlib.util.spec_from_file_location('skwd_config', SOURCE)
        helper = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(helper)
        self.write(self.config, {'steam': {'apiKey': 'chosen-secret'}})
        real_chmod = Path.chmod

        def chmod(path, mode, **kwargs):
            if path == self.legacy:
                raise PermissionError('private-secret-failure')
            return real_chmod(path, mode, **kwargs)

        diagnostics = io.StringIO()
        with mock.patch.object(Path, 'chmod', chmod), contextlib.redirect_stderr(diagnostics):
            helper.configure(self.home, MANAGED)
        self.assertEqual(self.load()['steam']['apiKey'], 'chosen-secret')
        self.assertNotIn('private-secret-failure', diagnostics.getvalue())
        self.assertIn('unreadable', diagnostics.getvalue())

    def test_malformed_dotenv_key_is_not_imported(self):
        for value in ('"unclosed-private-value', "'unclosed-private-value", 'bare"private-value'):
            with self.subTest(value=value):
                if self.config.exists():
                    self.config.unlink()
                self.secrets.write_text('STEAM_API_KEY=' + value + '\n')
                result = self.run_migration()
                self.assertNotIn('apiKey', self.load()['steam'])
                self.assertNotIn('private-value', result.stdout + result.stderr)

    def test_without_library_does_not_enable_steam_or_guess_an_account(self):
        self.legacy.unlink()
        self.run_migration()
        self.assertNotIn('steam', self.load()['features'])
        self.assertNotIn('username', self.load()['steam'])


if __name__ == '__main__':
    unittest.main()
