"""Exercise DMS's native directory migration with isolated XDG state."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile


def write(path, content):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content)


for upgrading in (False, True):
    with tempfile.TemporaryDirectory(prefix='dms-migration-') as directory:
        root = Path(directory)
        env = os.environ.copy()
        for kind in ('CONFIG', 'STATE', 'CACHE', 'DATA', 'RUNTIME'):
            path = root/kind.lower()
            path.mkdir(mode=0o700)
            env[f'XDG_{kind}_HOME' if kind != 'RUNTIME' else 'XDG_RUNTIME_DIR'] = str(path)

        # Home Manager owns the new settings and first-launch marker. On an
        # upgrade its old settings link is removed before DMS starts.
        managed = root/'managed-settings.json'
        write(managed, '{"matugenTemplateGhostty":false}\n')
        config = root/'config/dms'
        config.mkdir()
        (config/'settings.json').symlink_to(managed)
        write(config/'.firstlaunch', '')
        if upgrading:
            write(root/'config/DankMaterialShell/settings.json.backup', 'previous settings')

        # Activation and wallpaper preparation preserve the legacy session and
        # palette until the native CLI moves them, including disjoint caches.
        state = root/'state/DankMaterialShell/session.json'
        write(state, '{"wallpaperPath":"/saved.png","custom":42}\n')
        write(root/'cache/DankMaterialShell/dms-colors.json', 'saved palette')
        write(root/'cache/DankMaterialShell/clipboard/history', 'saved history')
        write(root/'cache/dms/clipboard/temporary', 'new clipboard entry')
        write(root/'data/DankMaterialShell/plugin-data', 'saved plugin data')

        for _ in range(2):
            result = subprocess.run([sys.argv[1], 'version'], env=env, text=True,
                                    capture_output=True, check=True, timeout=30)
            assert 'dir migration:' not in result.stderr, result.stderr
            for kind in ('state', 'cache', 'data') + (('config',) if upgrading else ()):
                legacy = root/kind/'DankMaterialShell'
                assert legacy.is_symlink(), legacy
                assert legacy.resolve() == (root/kind/'dms').resolve(), legacy
            assert state.read_text() == '{"wallpaperPath":"/saved.png","custom":42}\n'
            assert (config/'settings.json').is_symlink()
            assert (config/'settings.json').read_text() == managed.read_text()
            assert (config/'.firstlaunch').is_file()
            assert (root/'cache/dms/dms-colors.json').read_text() == 'saved palette'
            assert (root/'cache/dms/clipboard/history').read_text() == 'saved history'
            assert (root/'cache/dms/clipboard/temporary').read_text() == 'new clipboard entry'
            assert (root/'data/dms/plugin-data').read_text() == 'saved plugin data'

print('DMS native migration passed for fresh and existing installations, including repeat startup.')
