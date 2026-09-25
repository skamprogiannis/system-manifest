"""Runtime regressions for the wallpaper authority bridge (stdlib only)."""
import copy
import ctypes
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import socket
import subprocess
import sys
import threading
import unittest

SOURCE = Path(os.environ.get('WALLPAPER_SYNC_SOURCE', Path(__file__).parents[1] / 'modules/home/wallpaper/wallpaper-sync.py'))
spec = importlib.util.spec_from_file_location('wallpaper_sync', SOURCE)
sync = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sync)


class WallpaperSyncTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.paths = sync.Paths(self.root, self.root/'state', self.root/'cache', self.root/'config', self.root/'run')
        self.image = self.root/'80s Room.png'
        self.image.write_bytes(b'fixture image')
        self.last = {'type': 'static', 'path': str(self.image), 'thumb': str(self.image), 'we_id': ''}
        self.theme = {'key': 'static:80s Room.png', 'source': str(self.image), 'thumb': str(self.image), 'dark': True,
                      'palette': {'primary': '#ffb596'}, 'scheme': {'colors': {}}}
        for role in sync.REQUIRED_ROLES:
            self.theme['scheme']['colors'][role] = {'dark': {'color': '#ffb596'}, 'light': {'color': '#825400'}}
        self.write(self.paths.last, self.last)
        self.write(self.paths.outputs, {'DP-1': self.last})
        self.write(self.paths.session, {'wallpaperPath': '/old/Forge of Empires.png', 'isLightMode': False, 'notepadLastMode': 'slideout'})
        self.write(self.paths.settings, {'matugenTemplateGtk': True, 'matugenTemplateGhostty': False, 'runDmsMatugenTemplates': True})
        self.commands = []
        self.preview = False
        self.dms_unavailable = False
        self.rpc_unavailable = False
        self.bridge = sync.Bridge(self.paths, rpc=self.rpc, run=self.run_command, preview=lambda: self.preview)

    def write(self, path, value):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(value))

    def rpc(self, method):
        if self.rpc_unavailable:
            raise OSError('daemon restarting')
        self.assertEqual(method, 'theme.current')
        return copy.deepcopy(self.theme)

    def run_command(self, args, **kwargs):
        self.commands.append(args)
        if args[0] == self.bridge.magick:
            Path(args[-1]).write_bytes(b'PNG still')
        elif 'externalSet' in args:
            if self.dms_unavailable:
                raise sync.SyncError('DMS unavailable')
            session = sync.read_json(self.paths.session)
            session.update(sync.wallpaper_fields(args[-2], args[-1] == 'light'))
            self.write(self.paths.session, session)
        return ''

    def test_stale_dms_startup_palette_is_repaired(self):
        self.write(self.paths.palette, {'colors': {'dark': {'primary': '#81d2e6'}}})
        self.bridge.reconcile()
        self.assertEqual(sync.read_json(self.paths.palette)['colors']['dark']['primary'], '#ffb596')
        self.assertEqual(sync.read_json(self.paths.session)['wallpaperPath'], str(self.image))
        self.assertEqual(sync.read_json(self.paths.session)['notepadLastMode'], 'slideout')
        # A delayed old DMS worker overwrites the already committed palette.
        self.write(self.paths.palette, {'colors': {'dark': {'primary': '#81d2e6'}}})
        self.bridge.reconcile()
        self.assertEqual(sync.read_json(self.paths.palette)['colors']['dark']['primary'], '#ffb596')
        self.assertTrue(self.bridge.status()['palette_matches'])


    def test_qml_omitted_defaults_do_not_repeat_external_set(self):
        self.bridge.reconcile()
        session = sync.read_json(self.paths.session)
        for key in ('isLightMode', 'wallpaperCyclingEnabled', 'perMonitorWallpaper',
                    'perModeWallpaper', 'monitorWallpapers', 'monitorWallpapersLight',
                    'monitorWallpapersDark', 'monitorCyclingSettings'):
            session.pop(key, None)
        self.write(self.paths.session, session)
        before = sum('externalSet' in args for args in self.commands)
        self.bridge.reconcile()
        self.bridge.reconcile()
        self.assertEqual(sum('externalSet' in args for args in self.commands), before)
        # Omitted wallpaper paths are not defaults and still need repair.
        session.pop('wallpaperPathLight')
        self.write(self.paths.session, session)
        self.bridge.reconcile()
        self.assertEqual(sum('externalSet' in args for args in self.commands), before+1)

    def test_missing_mode_is_dark_when_new_applied_theme_is_light(self):
        self.theme['dark'] = False
        session = sync.read_json(self.paths.session)
        session.pop('isLightMode')
        self.write(self.paths.session, session)
        self.bridge.reconcile()
        self.assertTrue(sync.read_json(self.paths.session)['isLightMode'])

    def test_preview_never_replaces_snapshot_and_exit_restores_palette(self):
        self.bridge.reconcile()
        committed = self.paths.current.resolve()
        self.preview = True
        self.write(self.paths.palette, {'colors': {'dark': {'primary': '#123456'}}})
        self.bridge.reconcile()
        self.assertEqual(self.paths.current.resolve(), committed)
        self.assertEqual(sync.read_json(self.paths.palette)['colors']['dark']['primary'], '#123456')
        self.preview = False
        self.bridge.reconcile()
        self.assertEqual(sync.read_json(self.paths.palette)['colors']['dark']['primary'], '#ffb596')

    def test_new_apply_during_preview_commits_snapshot_without_overwriting_preview(self):
        self.bridge.reconcile()
        previous = self.paths.current.resolve()
        self.preview = True
        self.set_new_image('new picture.png')
        self.bridge.reconcile()
        self.assertNotEqual(self.paths.current.resolve(), previous)
        self.assertEqual(sync.read_json(self.paths.current/'metadata.json')['source'], str(self.image))

    def set_new_image(self, name):
        self.image = self.root/name
        self.image.write_bytes(b'new fixture')
        self.last.update(path=str(self.image), thumb=str(self.image))
        self.theme.update(key='static:'+name, source=str(self.image), thumb=str(self.image))
        self.write(self.paths.last, self.last)
        self.write(self.paths.outputs, {'DP-1': self.last})

    def test_superseded_completion_and_failed_generation_keep_previous_snapshot(self):
        self.bridge.reconcile()
        previous = self.paths.current.resolve()
        self.last['path'] = str(self.root/'new.png')
        self.write(self.paths.last, self.last)
        with self.assertRaises(sync.SyncError):
            self.bridge.reconcile()
        self.assertEqual(self.paths.current.resolve(), previous)

    def test_change_while_preparing_snapshot_is_rejected(self):
        original_run = self.bridge.run
        def change_after_conversion(args, **kwargs):
            result = original_run(args, **kwargs)
            if args[0] == self.bridge.magick:
                self.set_new_image('superseding.png')
            return result
        self.bridge.run = change_after_conversion
        with self.assertRaises(sync.SyncError):
            self.bridge.reconcile()
        self.assertFalse(self.paths.current.exists())

    def test_retry_dms_and_daemon_restart(self):
        self.dms_unavailable = True
        with self.assertRaises(sync.SyncError):
            self.bridge.reconcile()
        self.assertTrue(self.paths.current.exists())
        self.dms_unavailable = False
        self.bridge.reconcile()
        self.assertEqual(sync.read_json(self.paths.session)['wallpaperPath'], str(self.image))
        self.rpc_unavailable = True
        with self.assertRaises(OSError):
            self.bridge.reconcile()
        self.rpc_unavailable = False
        self.bridge.reconcile()
        self.assertTrue(self.bridge.status()['session_matches'])

    def test_animated_wallpaper_uses_still_and_immutable_greeter_path(self):
        video = self.root/'animated.webm'
        video.write_bytes(b'video')
        self.last.update(type='video', path=str(video))
        self.theme['key'] = 'video:animated.webm'
        self.write(self.paths.last, self.last)
        self.write(self.paths.outputs, {'DP-1': self.last})
        self.bridge.reconcile()
        session = sync.read_json(self.paths.current/'session.json')
        self.assertEqual(session['wallpaperPath'], str(self.paths.current.resolve()/'wallpaper.png'))
        self.assertTrue(Path(session['wallpaperPath']).is_file())
        self.assertNotEqual(sync.read_json(self.paths.session)['wallpaperPath'], str(video))

    def test_missing_image_and_malformed_palette_fail_closed(self):
        self.bridge.reconcile()
        previous = self.paths.current.resolve()
        self.set_new_image('missing.png')
        self.image.unlink()
        with self.assertRaises(sync.SyncError):
            self.bridge.reconcile()
        self.assertEqual(self.paths.current.resolve(), previous)
        self.theme['scheme']['colors']['primary']['dark']['color'] = 'bad'
        with self.assertRaises(sync.SyncError):
            self.bridge.reconcile()

    def test_prepare_updates_session_offline_preserving_preferences(self):
        self.bridge.reconcile()
        self.write(self.paths.session, {'wallpaperPath': '/old.png', 'isLightMode': True, 'custom': 42})
        self.rpc_unavailable = True
        self.bridge.prepare()
        session = sync.read_json(self.paths.session)
        self.assertEqual(session['custom'], 42)
        self.assertTrue(session['isLightMode'])
        self.assertEqual(session['wallpaperPath'], str(self.image))

    def test_mode_changes_survive_reconciliation(self):
        self.bridge.reconcile()
        session = sync.read_json(self.paths.session)
        session['isLightMode'] = True
        self.write(self.paths.session, session)
        self.bridge.reconcile()
        self.assertTrue(sync.read_json(self.paths.session)['isLightMode'])
        self.assertEqual(sync.read_json(self.paths.palette)['mode'], 'light')
        self.assertTrue(sync.read_json(self.paths.current/'session.json')['isLightMode'])

    def test_templates_use_stock_roles_separate_cache_and_skip_flags(self):
        self.bridge.reconcile()
        command = next(args for args in self.commands if 'generate' in args)
        self.assertEqual(command[1:3], ['matugen', 'generate'])
        self.assertNotEqual(command[command.index('--state-dir')+1], str(self.paths.palette.parent))
        stock = json.loads(command[command.index('--stock-colors')+1])
        self.assertEqual(stock['primary']['dark']['color'], '#ffb596')
        skips = command[command.index('--skip-templates')+1].split(',')
        self.assertIn('ghostty', skips)
        self.assertIn('hyprland', skips)
        self.assertNotIn('gtk', skips)



    def test_unchanged_reconciliation_lock_does_not_signal_state_write(self):
        self.paths.root.mkdir(parents=True)
        libc = ctypes.CDLL(None, use_errno=True)
        descriptor = libc.inotify_init1(os.O_NONBLOCK | os.O_CLOEXEC)
        self.assertGreaterEqual(descriptor, 0)
        try:
            watch = libc.inotify_add_watch(descriptor, os.fsencode(self.paths.root), 0x00000008)
            self.assertGreaterEqual(watch, 0)
            with self.bridge.lock():
                pass
            with self.bridge.lock():
                pass
            with self.assertRaises(BlockingIOError):
                os.read(descriptor, 4096)
        finally:
            os.close(descriptor)

    def test_cli_prepare_does_not_wait_for_running_reconciler(self):
        self.bridge.reconcile()
        environment = dict(os.environ, XDG_STATE_HOME=str(self.root/'state'),
                           XDG_CACHE_HOME=str(self.root/'cache'), XDG_CONFIG_HOME=str(self.root/'config'),
                           XDG_RUNTIME_DIR=str(self.root/'run'))
        with self.bridge.lock():
            result = subprocess.run([sys.executable, str(SOURCE), 'prepare'], env=environment,
                                    text=True, capture_output=True, timeout=2, check=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('restoration deferred', result.stderr)

    def test_socket_rpc_reads_newline_delimited_applied_theme(self):
        self.paths.socket.parent.mkdir(parents=True)
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as server:
            server.bind(str(self.paths.socket))
            server.listen(1)
            requests = []
            def respond():
                connection, _ = server.accept()
                with connection, connection.makefile('rb') as reader:
                    request = json.loads(reader.readline())
                    requests.append(request)
                    connection.sendall((json.dumps({'id': request['id'], 'result': self.theme})+'\n').encode())
            worker = threading.Thread(target=respond, daemon=True)
            worker.start()
            self.assertEqual(sync.Bridge(self.paths).call('theme.current'), self.theme)
            worker.join(timeout=2)
            self.assertFalse(worker.is_alive())
            self.assertEqual(requests[0]['method'], 'theme.current')

    def test_matugen_unchanged_exit_status_is_success(self):
        self.assertEqual(sync.Bridge.command([sys.executable, '-c', 'import sys; sys.exit(2)'], success=(0, 2)), '')

    def test_status_is_read_only(self):
        self.bridge.reconcile()
        before = {p: p.stat().st_mtime_ns for p in self.root.rglob('*') if p.is_file()}
        commands = len(self.commands)
        self.bridge.status()
        self.assertEqual(commands, len(self.commands))
        self.assertEqual(before, {p: p.stat().st_mtime_ns for p in self.root.rglob('*') if p.is_file()})


if __name__ == '__main__':
    unittest.main()
