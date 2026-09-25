#!/usr/bin/env python3
"""Copy a committed user wallpaper snapshot into the greeter's own state."""
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import stat
import sys
import tempfile

WALLPAPER_KEYS = ('wallpaperPath', 'wallpaperPathLight', 'wallpaperPathDark')
PNG_HEADER = b'\x89PNG\r\n\x1a\n'


class PublishError(Exception):
    pass


def read_regular(directory_fd, name, owner, limit):
    """Pin regular files owned by the snapshot user; never follow user symlinks."""
    fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=directory_fd)
    with os.fdopen(fd, 'rb') as file:
        info = os.fstat(file.fileno())
        if not stat.S_ISREG(info.st_mode) or info.st_uid != owner or info.st_size > limit:
            raise PublishError(f'Invalid snapshot file: {name}')
        data = file.read(limit+1)
        if len(data) > limit:
            raise PublishError(f'Snapshot file too large: {name}')
        return data


def load_snapshot(current):
    current = Path(current)
    root = current.parent.resolve(strict=True)
    source = current.resolve(strict=True)
    if source.parent != root or not source.name.startswith('generation-'):
        raise PublishError('Current snapshot must be a generation inside the wallpaper state directory')
    directory_fd = os.open(source, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        owner = os.fstat(directory_fd).st_uid
        if owner != root.stat().st_uid:
            raise PublishError('Snapshot directory owner does not match wallpaper state owner')
        session = json.loads(read_regular(directory_fd, 'session.json', owner, 4*1024*1024))
        colors = json.loads(read_regular(directory_fd, 'dms-colors.json', owner, 4*1024*1024))
        wallpaper = read_regular(directory_fd, 'wallpaper.png', owner, 128*1024*1024)
    finally:
        os.close(directory_fd)
    if not isinstance(session, dict) or not isinstance(colors, dict):
        raise PublishError('Snapshot session and palette must be objects')
    if any(session.get(key) != str(source/'wallpaper.png') for key in WALLPAPER_KEYS):
        raise PublishError('Snapshot wallpaper fields do not refer to its committed still')
    if not wallpaper.startswith(PNG_HEADER):
        raise PublishError('Snapshot still is not a PNG')
    mode = 'light' if session.get('isLightMode', False) else 'dark'
    if colors.get('mode') != mode:
        raise PublishError('Snapshot session and palette modes differ')
    for variant in ('dark', 'light'):
        roles = colors.get('colors', {}).get(variant)
        if not isinstance(roles, dict) or not roles.get('primary'):
            raise PublishError(f'Missing {variant} palette')
        if not all(isinstance(color, str) and re.fullmatch(r'#[0-9a-fA-F]{6}', color) for color in roles.values()):
            raise PublishError(f'Invalid {variant} color')
    fingerprint = hashlib.sha256(json.dumps({'source': str(source), 'session': session,
                                            'colors': colors}, sort_keys=True).encode()+wallpaper).hexdigest()
    return source, session, colors, wallpaper, fingerprint


def write_file(path, data):
    with path.open('xb') as file:
        file.write(data)
        file.flush()
        os.fsync(file.fileno())
    path.chmod(0o644)


def replace_link(path, target):
    temporary = path.parent/(f'.{path.name}-{os.getpid()}')
    temporary.unlink(missing_ok=True)
    temporary.symlink_to(target)
    os.replace(temporary, path)


def stable_links_valid(destination):
    return all((destination/name).is_symlink() and os.readlink(destination/name) == f'wallpaper-current/{name}'
               for name in ('session.json', 'colors.json'))


def publish(current, destination):
    destination = Path(destination)
    destination.mkdir(mode=0o750, parents=True, exist_ok=True)
    with (destination/'.wallpaper-sync.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        source, session, colors, wallpaper, fingerprint = load_snapshot(current)
        try:
            marker = json.loads((destination/'wallpaper-current/source.json').read_text())
            existing_valid = all((destination/'wallpaper-current'/name).is_file()
                                 for name in ('session.json', 'colors.json', 'wallpaper.png'))
            if marker.get('fingerprint') == fingerprint and existing_valid and stable_links_valid(destination):
                return False
        except (OSError, ValueError):
            pass
        generation = Path(tempfile.mkdtemp(prefix='wallpaper-generation-', dir=destination))
        generation.chmod(0o755)
        published = False
        try:
            session.update(dict.fromkeys(WALLPAPER_KEYS, str(generation/'wallpaper.png')))
            write_file(generation/'wallpaper.png', wallpaper)
            for name, value in (('session.json', session), ('colors.json', colors),
                                ('source.json', {'source': str(source), 'fingerprint': fingerprint})):
                write_file(generation/name, (json.dumps(value, sort_keys=True, indent=2)+'\n').encode())
            replace_link(destination/'wallpaper-current', generation.name)
            published = True
            # Only initial migration needs to replace legacy standalone files.
            for name in ('session.json', 'colors.json'):
                path = destination/name
                if not path.is_symlink() or os.readlink(path) != f'wallpaper-current/{name}':
                    replace_link(path, f'wallpaper-current/{name}')
            return True
        finally:
            if not published:
                shutil.rmtree(generation)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path, help='user wallpaper-sync/current symlink')
    parser.add_argument('destination', type=Path, help='greeter state directory')
    args = parser.parse_args()
    try:
        if publish(args.source, args.destination):
            print('Greeter wallpaper snapshot updated')
    except (OSError, ValueError, TypeError, PublishError) as error:
        # Missing first-boot state or malformed input must never prevent login.
        print(f'Greeter wallpaper snapshot retained: {error}', file=sys.stderr)
    return 0


if __name__ == '__main__':
    sys.exit(main())
