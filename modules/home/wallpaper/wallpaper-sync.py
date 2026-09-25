#!/usr/bin/env python3
"""Publish skwd-wall's applied wallpaper and colors as one durable snapshot."""
import argparse
from contextlib import contextmanager
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import select
import shutil
import socket
import subprocess
import sys
import tempfile
import time

REQUIRED_ROLES = ('primary', 'on_primary', 'surface', 'on_surface', 'background', 'outline')
WALLPAPER_KEYS = ('wallpaperPath', 'wallpaperPathLight', 'wallpaperPathDark')
# SessionData omits properties equal to their QML defaults when saving.
SESSION_DEFAULTS = {
    'isLightMode': False, 'wallpaperCyclingEnabled': False,
    'perMonitorWallpaper': False, 'perModeWallpaper': False,
    'monitorWallpapers': {}, 'monitorWallpapersLight': {},
    'monitorWallpapersDark': {}, 'monitorCyclingSettings': {},
}
TEMPLATES = {
    'Gtk': 'gtk', 'Niri': 'niri', 'Hyprland': 'hyprland', 'Mangowc': 'mangowc',
    'Qt5ct': 'qt5ct', 'Qt6ct': 'qt6ct', 'Qtengine': 'qtengine', 'Fcitx5': 'fcitx5',
    'Firefox': 'firefox', 'Pywalfox': 'pywalfox', 'ZenBrowser': 'zenbrowser',
    'Vesktop': 'vesktop', 'Vencord': 'vencord', 'Equibop': 'equibop',
    'Ghostty': 'ghostty', 'Kitty': 'kitty', 'Foot': 'foot', 'Neovim': 'nvim',
    'Alacritty': 'alacritty', 'Wezterm': 'wezterm', 'Dgop': 'dgop',
    'Kcolorscheme': 'kcolorscheme', 'Vscode': 'vscode', 'Emacs': 'emacs', 'Zed': 'zed',
}


class SyncError(Exception):
    pass


class Paths:
    def __init__(self, home=None, state=None, cache=None, config=None, runtime=None):
        home = Path(home or Path.home())
        state = Path(state or os.environ.get('XDG_STATE_HOME', home/'.local/state'))
        cache = Path(cache or os.environ.get('XDG_CACHE_HOME', home/'.cache'))
        config = Path(config or os.environ.get('XDG_CONFIG_HOME', home/'.config'))
        runtime = Path(runtime or os.environ.get('XDG_RUNTIME_DIR', f'/run/user/{os.getuid()}'))
        self.root = state/'wallpaper-sync'
        self.current = self.root/'current'
        self.pending = self.root/'status.json'
        self.session = state/'DankMaterialShell/session.json'
        self.settings = config/'DankMaterialShell/settings.json'
        self.config = config
        self.palette = cache/'DankMaterialShell/dms-colors.json'
        self.templates = cache/'wallpaper-sync/templates'
        self.last = cache/'skwd-wall-v2/last-wallpaper.json'
        self.outputs = cache/'skwd-wall-v2/outputs.json'
        self.socket = runtime/'skwd-wall-v2/wall.sock'


def read_json(path, default=None):
    try:
        value = json.loads(Path(path).read_text())
    except FileNotFoundError:
        if default is not None:
            return default
        raise
    if not isinstance(value, dict):
        raise SyncError(f'Expected JSON object: {path}')
    return value


def atomic_json(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    data = json.dumps(value, sort_keys=True, indent=2)+'\n'
    if path.is_file() and path.read_text() == data:
        return
    fd, temporary = tempfile.mkstemp(prefix='.'+path.name, dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as file:
            file.write(data)
            file.flush()
            os.fsync(file.fileno())
        os.chmod(temporary, 0o644)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True).encode()).hexdigest()


def wallpaper_fields(source, light):
    return {**dict.fromkeys(WALLPAPER_KEYS, source), 'isLightMode': light,
            'wallpaperCyclingEnabled': False, 'perMonitorWallpaper': False,
            'perModeWallpaper': False, 'monitorWallpapers': {},
            'monitorWallpapersLight': {}, 'monitorWallpapersDark': {},
            'monitorCyclingSettings': {}}


def material_colors(theme, light):
    roles = theme.get('scheme', {}).get('colors', {})
    if not isinstance(roles, dict) or any(key not in roles for key in REQUIRED_ROLES):
        raise SyncError('Applied theme has no complete Material scheme')
    colors = {}
    for role, variants in roles.items():
        if not isinstance(variants, dict) or 'dark' not in variants or 'light' not in variants:
            continue
        colors[role] = {}
        for mode in ('dark', 'light'):
            value = variants[mode]
            color = value.get('color') if isinstance(value, dict) else value
            if not isinstance(color, str) or not re.fullmatch(r'#[0-9a-fA-F]{6}', color):
                raise SyncError(f'Invalid {mode} color for {role}')
            colors[role][mode] = color.lower()
        colors[role]['default'] = colors[role]['light' if light else 'dark']
    if any(key not in colors for key in REQUIRED_ROLES):
        raise SyncError('Applied Material scheme is incomplete')
    return {'mode': 'light' if light else 'dark',
            'colors': {mode: {role: variants[mode] for role, variants in colors.items()}
                       for mode in ('dark', 'light')}}


def applied_identity(last):
    kind = last.get('type')
    path = last.get('path', '')
    if kind not in ('static', 'video', 'we'):
        raise SyncError(f'Unsupported applied wallpaper type: {kind}')
    key = f"we:{last.get('we_id', '')}" if kind == 'we' else f'{kind}:{Path(path).name}'
    return {'type': kind, 'path': path, 'we_id': last.get('we_id', ''), 'key': key}


class Bridge:
    def __init__(self, paths=None, rpc=None, run=None, preview=None):
        self.paths = paths or Paths()
        self.dms = os.environ.get('WALLPAPER_SYNC_DMS', shutil.which('dms') or '/run/current-system/sw/bin/dms')
        self.magick = os.environ.get('WALLPAPER_SYNC_MAGICK', shutil.which('magick') or '/run/current-system/sw/bin/magick')
        self.helm = os.environ.get('WALLPAPER_SYNC_HELM', shutil.which('skwd-helm') or '/run/current-system/sw/bin/skwd-helm')
        self.shell = os.environ.get('WALLPAPER_SYNC_SHELL_DIR', '/etc/xdg/quickshell/dms')
        self.rpc = rpc or self.call
        self.run = run or self.command
        self.preview = preview or self.picker_open

    @staticmethod
    def command(args, timeout=30, success=(0,)):
        result = subprocess.run(args, text=True, capture_output=True, timeout=timeout, check=False)
        if result.returncode not in success:
            message = result.stderr.strip() or result.stdout.strip()
            raise SyncError(f'{Path(args[0]).name} failed ({result.returncode}): {message[:500]}')
        return result.stdout.strip()

    def call(self, method):
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
            connection.settimeout(3)
            connection.connect(str(self.paths.socket))
            connection.sendall((json.dumps({'id': 1, 'method': method, 'params': {}})+'\n').encode())
            with connection.makefile('rb') as reader:
                response = json.loads(reader.readline(4*1024*1024))
        if 'error' in response or not isinstance(response.get('result'), dict):
            raise SyncError(f'{method}: {response.get("error", "missing result")}')
        return response['result']

    def picker_open(self):
        # Preview state is private to skwd's client. Its control socket is a
        # conservative lease: do not heal transient colors while it is open.
        try:
            state = json.loads(self.command([self.helm, 'ui', 'state'], timeout=2))
            return state.get('visible', state.get('open', True)) is not False
        except (OSError, ValueError, SyncError, subprocess.TimeoutExpired):
            return False

    def applied(self):
        last = read_json(self.paths.last)
        identity = applied_identity(last)
        theme = self.rpc('theme.current')
        # Matugen may be reading a generated thumbnail, not the source image.
        candidates = {identity['key'], identity['path'], last.get('thumb')}
        if theme.get('key') not in candidates:
            raise SyncError('Waiting for the latest applied wallpaper theme')
        outputs = read_json(self.paths.outputs)
        if not any(applied_identity(value) == identity for value in outputs.values() if isinstance(value, dict)):
            raise SyncError('Applied wallpaper is not active on any output')
        material_colors(theme, False)
        return last, identity, theme

    def fingerprint(self, identity, theme):
        return digest({'identity': identity, 'theme': theme})

    def source(self, last, theme):
        candidates = [last.get('path')] if last['type'] == 'static' else [theme.get('thumb'), last.get('thumb'), theme.get('source')]
        for candidate in candidates:
            if candidate and Path(candidate).is_file():
                return str(Path(candidate).resolve())
        raise SyncError('Applied wallpaper still is missing; retaining previous snapshot')

    def snapshot(self, last, identity, theme, light, fingerprint):
        source = self.source(last, theme)
        self.paths.root.mkdir(parents=True, exist_ok=True)
        directory = Path(tempfile.mkdtemp(prefix='generation-', dir=self.paths.root))
        os.chmod(directory, 0o755)
        try:
            still = directory/'wallpaper.png'
            self.run([self.magick, source+'[0]', '-auto-orient', '-strip', str(still)], timeout=45)
            if not still.is_file() or still.stat().st_size == 0:
                raise SyncError('Wallpaper still conversion produced no image')
            session = read_json(self.paths.session, {})
            session.update(wallpaper_fields(str(still), light))
            atomic_json(directory/'session.json', session)
            atomic_json(directory/'dms-colors.json', material_colors(theme, light))
            atomic_json(directory/'metadata.json', {'fingerprint': fingerprint, 'identity': identity,
                        'source': source, 'theme_source': theme.get('source'), 'key': theme.get('key'),
                        'light': light, 'committed_at': time.time()})
            # Conversion can be slow. Re-read both inputs before publication.
            _, latest_identity, latest_theme = self.applied()
            if self.fingerprint(latest_identity, latest_theme) != fingerprint:
                raise SyncError('Wallpaper changed during snapshot preparation')
            temporary = self.paths.root/f'.current-{os.getpid()}'
            temporary.unlink(missing_ok=True)
            temporary.symlink_to(directory.name)
            os.replace(temporary, self.paths.current)
            # Keep generations: greeter readers may already have resolved one.
            return directory
        except BaseException:
            shutil.rmtree(directory)
            raise

    def render_templates(self, palette, settings, fingerprint):
        render_key = digest({'theme': fingerprint, 'mode': palette['mode'], 'settings': settings})
        marker = self.paths.templates/'rendered.json'
        if read_json(marker, {}).get('key') == render_key:
            return
        self.paths.templates.mkdir(parents=True, exist_ok=True)
        stock = {role: {mode: {'color': palette['colors'][mode][role]}
                        for mode in ('dark', 'light')}
                 for role in palette['colors']['dark']}
        for variants in stock.values():
            variants['default'] = variants[palette['mode']]
        skip = {'hyprland'}
        for setting, template in TEMPLATES.items():
            if not settings.get('runDmsMatugenTemplates', True) or not settings.get('matugenTemplate'+setting, setting != 'Neovim'):
                skip.add(template)
        args = [self.dms, 'matugen', 'generate', '--state-dir', str(self.paths.templates),
                '--shell-dir', self.shell, '--config-dir', str(self.paths.config), '--kind', 'hex',
                '--value', palette['colors']['dark']['primary'], '--mode', palette['mode'],
                '--stock-colors', json.dumps(stock), '--skip-templates', ','.join(sorted(skip)),
                '--icon-theme', settings.get('iconThemeLight' if settings.get('iconThemePerMode', False) and palette['mode'] == 'light' else 'iconThemeDark', settings.get('iconTheme', 'System Default'))]
        if not settings.get('runUserMatugenTemplates', True):
            args.append('--run-user-templates=false')
        if settings.get('terminalsAlwaysDark', False):
            args.append('--terminals-always-dark')
        if settings.get('syncModeWithPortal', True):
            args.append('--sync-mode-with-portal')
        self.run(args, timeout=90, success=(0, 2))
        atomic_json(marker, {'key': render_key})

    def reconcile(self):
        last, identity, theme = self.applied()
        fingerprint = self.fingerprint(identity, theme)
        previous = read_json(self.paths.current/'metadata.json', {})
        session = read_json(self.paths.session, {})
        light = bool(session.get('isLightMode', False)) if previous.get('fingerprint') == fingerprint else not theme.get('dark', True)
        if previous.get('fingerprint') != fingerprint or previous.get('light') != light:
            directory = self.snapshot(last, identity, theme, light, fingerprint)
        else:
            directory = self.paths.current.resolve(strict=True)
        metadata = read_json(directory/'metadata.json')
        palette = read_json(directory/'dms-colors.json')
        source = metadata['source'] if Path(metadata['source']).is_file() else str(directory/'wallpaper.png')
        wanted = wallpaper_fields(source, light)
        if any(session.get(key, SESSION_DEFAULTS.get(key)) != value for key, value in wanted.items()):
            response = self.run([self.dms, 'ipc', 'call', 'wallpaper', 'externalSet', source, 'light' if light else 'dark'], timeout=5)
            if response.startswith('ERROR'):
                raise SyncError(response)
        if not self.preview():
            atomic_json(self.paths.palette, palette)
            self.render_templates(palette, read_json(self.paths.settings, {}), fingerprint)
        return metadata

    def prepare(self):
        # ExecStartPre calls this before QML starts: only then is a direct session
        # update safe. Never wait for a daemon or unavailable IPC on this path.
        if not self.paths.current.exists():
            return
        directory = self.paths.current.resolve(strict=True)
        metadata = read_json(directory/'metadata.json')
        snapshot_session = read_json(directory/'session.json')
        palette = read_json(directory/'dms-colors.json')
        still = Path(snapshot_session['wallpaperPath'])
        if not still.is_file() or not palette.get('colors'):
            raise SyncError('Incomplete wallpaper snapshot')
        session = read_json(self.paths.session, {})
        light = bool(session.get('isLightMode', metadata['light']))
        source = metadata['source'] if Path(metadata['source']).is_file() else str(still)
        session.update(wallpaper_fields(source, light))
        atomic_json(self.paths.session, session)
        palette['mode'] = 'light' if light else 'dark'
        atomic_json(self.paths.palette, palette)

    def status(self):
        result = {'applied_source': None, 'synchronized_source': None, 'palette_matches': False,
                  'session_matches': False, 'snapshot_matches': False, 'preview_active': self.preview(),
                  'pending_error': read_json(self.paths.pending, {}).get('error')}
        try:
            _, identity, theme = self.applied()
            result['applied_source'] = identity['path'] or theme.get('source')
            directory = self.paths.current.resolve(strict=True)
            metadata = read_json(directory/'metadata.json')
            result['synchronized_source'] = metadata['source']
            result['snapshot_matches'] = metadata['fingerprint'] == self.fingerprint(identity, theme)
            committed = read_json(directory/'dms-colors.json')
            live = read_json(self.paths.palette, {})
            result['palette_matches'] = live.get('colors') == committed.get('colors') and live.get('mode') == committed.get('mode')
            session = read_json(self.paths.session, {})
            result['session_matches'] = all(session.get(key) in (metadata['source'], str(directory/'wallpaper.png')) for key in WALLPAPER_KEYS)
            result['snapshot'] = str(directory)
        except (OSError, ValueError, SyncError, KeyError) as error:
            result['pending_error'] = str(error)
        return result

    @contextmanager
    def lock(self, blocking=True):
        self.paths.root.mkdir(parents=True, exist_ok=True)
        # A read descriptor avoids IN_CLOSE_WRITE waking the greeter publisher.
        descriptor = os.open(self.paths.root/'lock', os.O_RDONLY | os.O_CREAT | os.O_CLOEXEC, 0o600)
        with os.fdopen(descriptor, 'r') as file:
            fcntl.flock(file, fcntl.LOCK_EX | (0 if blocking else fcntl.LOCK_NB))
            yield

    def attempt(self):
        error = None
        try:
            with self.lock():
                self.reconcile()
        except (OSError, ValueError, SyncError, KeyError, subprocess.TimeoutExpired) as failure:
            error = str(failure)
        old = read_json(self.paths.pending, {}).get('error')
        if old != error:
            print('wallpaper-sync: '+(error or 'applied wallpaper and palette synchronized'), file=sys.stderr, flush=True)
        atomic_json(self.paths.pending, {'error': error})
        return error is None

    def watch(self):
        # Subscribe before the first read so applies during startup cannot be lost.
        # A periodic reconciliation heals crashed consumers and interrupted previews.
        while True:
            try:
                with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
                    connection.settimeout(3)
                    connection.connect(str(self.paths.socket))
                    connection.sendall(b'{"id":1,"method":"subscribe","params":{}}\n')
                    self.attempt()
                    buffer = b''
                    while True:
                        ready, _, _ = select.select([connection], [], [], 3)
                        if not ready:
                            self.attempt()
                            continue
                        data = connection.recv(65536)
                        if not data:
                            raise OSError('skwd-wall disconnected')
                        buffer += data
                        if len(buffer) > 4*1024*1024:
                            raise SyncError('skwd-wall event exceeds size limit')
                        while b'\n' in buffer:
                            line, buffer = buffer.split(b'\n', 1)
                            event = json.loads(line)
                            if event.get('event') == 'skwd.wall.theme_done' and event.get('data', {}).get('ok', True):
                                self.attempt()
            except (OSError, ValueError, SyncError) as error:
                atomic_json(self.paths.pending, {'error': str(error)})
                time.sleep(3)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=('watch', 'reconcile', 'prepare', 'status'))
    parser.add_argument('--json', action='store_true', help='print machine-readable status')
    args = parser.parse_args()
    bridge = Bridge()
    if args.command == 'status':
        status = bridge.status()
        if args.json:
            print(json.dumps(status, indent=2))
        else:
            for key, value in status.items():
                print(f'{key.replace("_", " ")}: {value}')
        return 0
    if args.command == 'prepare':
        try:
            with bridge.lock(blocking=False):
                bridge.prepare()
        except (OSError, ValueError, KeyError, SyncError) as error:
            print(f'wallpaper-sync: startup restoration deferred: {error}', file=sys.stderr)
        return 0
    if args.command == 'reconcile':
        return 0 if bridge.attempt() else 1
    bridge.watch()
    return 0


if __name__ == '__main__':
    sys.exit(main())
