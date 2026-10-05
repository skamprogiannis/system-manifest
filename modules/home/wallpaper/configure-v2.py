"""Manage the v2 colour contract and seed missing local v1 Steam settings."""
import argparse
import copy
import json
import os
from pathlib import Path
import re
import sys
import tempfile


def warn(message):
    # Never include parser exceptions, file contents, or account identifiers.
    print('configureSkwdWallV2Theming: ' + message, file=sys.stderr)


def json_object(path):
    try:
        path.chmod(0o600)
        value = json.loads(path.read_text())
        if not isinstance(value, dict):
            raise ValueError()
        return value
    except FileNotFoundError:
        return {}
    except (OSError, UnicodeError, ValueError):
        warn('ignoring unreadable or malformed legacy configuration')
        return {}


def section(config, name):
    value = config.get(name)
    return value if isinstance(value, dict) else {}


def string(value):
    return value if isinstance(value, str) and value.strip() else None


def fill(config, group, key, value):
    if value is None:
        return
    if config.get(group) is None:
        config[group] = {}
    target = config[group]
    if isinstance(target, dict) and (key not in target or target[key] is None or target[key] == ''):
        target[key] = value


def literal_api_key(path):
    if not path.exists():
        return None
    try:
        path.chmod(0o600)
        for line in path.read_text().splitlines():
            match = re.fullmatch(r'\s*(?:export\s+)?STEAM_API_KEY\s*=\s*(.*?)\s*', line)
            if not match:
                continue
            value = match[1]
            if value.startswith(('"', "'")):
                quote = value[0]
                if len(value) < 2 or value[-1] != quote or quote in value[1:-1]:
                    warn('ignoring malformed legacy Steam credential')
                    return None
                value = value[1:-1]
            elif '"' in value or "'" in value:
                warn('ignoring malformed legacy Steam credential')
                return None
            # This is a literal value, never shell code or environment expansion.
            return string(value)
    except (OSError, UnicodeError):
        warn('could not read private legacy Steam credential')
    return None


def read_vdf(path):
    """Read the small quoted KeyValues files Steam writes; reject ambiguity."""
    try:
        source = path.read_text()
        tokens = []
        cursor = 0
        pattern = re.compile(r'\s+|//[^\n]*|"((?:[^"\\]|\\.)*)"|[{}]')
        while cursor < len(source):
            match = pattern.match(source, cursor)
            if match is None:
                raise ValueError()
            token = match[0]
            cursor = match.end()
            if token.isspace() or token.startswith('//'):
                continue
            tokens.append(('string', re.sub(r'\\(["\\])', r'\1', match[1])) if match[1] is not None else (token, token))
        position = 0

        def object_(nested=False):
            nonlocal position
            value = {}
            while position < len(tokens):
                kind, key = tokens[position]
                position += 1
                if kind == '}' and nested:
                    return value
                if kind != 'string' or key in value or position == len(tokens):
                    raise ValueError()
                kind, item = tokens[position]
                position += 1
                if kind == '{':
                    value[key] = object_(True)
                elif kind == 'string':
                    value[key] = item
                else:
                    raise ValueError()
            if nested:
                raise ValueError()
            return value

        return object_()
    except FileNotFoundError:
        return {}
    except (OSError, UnicodeError, ValueError, RecursionError):
        warn('ignoring malformed Steam metadata')
        return {}


def local_path(value, home):
    if not string(value):
        return None
    if value == '~':
        return home
    if value.startswith('~/'):
        return home / value[2:]
    path = Path(value)
    return path if path.is_absolute() else None


def steam_settings(config, legacy, home):
    old_paths, old_steam = section(legacy, 'paths'), section(legacy, 'steam')
    new_paths = section(config, 'paths')
    root = next((path.resolve() for path in (home / '.steam/root', home / '.local/share/Steam') if path.is_dir()), None)
    for name in ('steamWorkshop', 'steamWeAssets'):
        fill(config, 'paths', name, string(old_paths.get(name)))
    fill(config, 'paths', 'steam', str(root) if root else None)
    fill(config, 'steam', 'backend', 'steamcmd')
    fill(config, 'steam', 'apiKey', string(old_steam.get('apiKey')) or literal_api_key(home / '.config/skwd-wall/secrets.env'))
    # Tighten the legacy credential even when an old JSON key took precedence.
    secrets = home / '.config/skwd-wall/secrets.env'
    if secrets.exists():
        try:
            secrets.chmod(0o600)
        except OSError:
            warn('could not secure legacy Steam credential')

    libraries = set()
    if root:
        libraries.add(root / 'steamapps')
    old_root = local_path(old_paths.get('steam'), home)
    if old_root:
        libraries.add(old_root / 'steamapps')
    for paths in (old_paths, new_paths):
        for name in ('steamWorkshop', 'steamWeAssets'):
            path = local_path(paths.get(name), home)
            if path:
                for parent in path.parents:
                    if parent.name == 'steamapps':
                        libraries.add(parent)
                        break
    owners = set()
    library_found = False
    for library in libraries:
        manifest = library / 'appmanifest_431960.acf'
        state = section(read_vdf(manifest), 'AppState')
        if state.get('appid') == '431960':
            library_found = True
            owner = string(state.get('LastOwner'))
            if owner and owner.isdecimal():
                owners.add(owner)
    if any((local_path(section(config, 'paths').get(name), home) or home / '.missing-steam-path').is_dir()
           for name in ('steamWorkshop', 'steamWeAssets')):
        library_found = True
    if library_found:
        fill(config, 'features', 'steam', True)
    username = string(old_steam.get('username'))
    if not username and len(owners) == 1 and root:
        users = section(read_vdf(root / 'config/loginusers.vdf'), 'users')
        username = string(section(users, next(iter(owners))).get('AccountName'))
    fill(config, 'steam', 'username', username)


def merge_theme(config, managed):
    integrations = config.get('integrations')
    if not isinstance(integrations, list):
        integrations = []
    config['integrations'] = [item for item in integrations if not isinstance(item, dict) or item.get('name') != 'system-manifest-dms-preview'] + managed.get('integrations', [])
    for name, value in managed.items():
        if name == 'integrations':
            continue
        if isinstance(value, dict):
            existing = config.get(name)
            config[name] = {**(existing if isinstance(existing, dict) else {}), **value}
        else:
            config[name] = value


def private_backup(path, contents):
    try:
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    except FileExistsError:
        fd = os.open(path, os.O_WRONLY | os.O_NOFOLLOW)
        try:
            os.fchmod(fd, 0o600)
        finally:
            os.close(fd)
        return
    try:
        with os.fdopen(fd, 'wb') as stream:
            os.fchmod(stream.fileno(), 0o600)
            stream.write(contents)
            stream.flush()
            os.fsync(stream.fileno())
    except BaseException:
        # Only this branch owns a newly created backup. A partial write must
        # not be mistaken for the preserved original by the next activation.
        path.unlink(missing_ok=True)
        raise


def configure(home, managed):
    path = home / '.config/skwd-wall-v2/config.json'
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    original = path.read_bytes() if path.exists() else None
    invalid = False
    try:
        config = json.loads(original) if original else {}
        if not isinstance(config, dict):
            raise ValueError()
    except (UnicodeError, ValueError):
        invalid = True
        config = {}
        warn('preserving malformed v2 configuration in a private backup')
    before = copy.deepcopy(config)
    legacy = json_object(home / '.config/skwd-wall/config.json')
    steam_settings(config, legacy, home)
    merge_theme(config, managed)
    if original is not None:
        path.chmod(0o600)
        if invalid:
            private_backup(path.with_name('config.json.invalid'), original)
        elif config != before:
            private_backup(path.with_name('config.json.pre-steam-v2'), original)
        else:
            return
    fd, temporary = tempfile.mkstemp(prefix='.config.json.', dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as stream:
            os.fchmod(stream.fileno(), 0o600)
            json.dump(config, stream, indent=2, ensure_ascii=False)
            stream.write('\n')
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--home', type=Path, default=Path.home())
    parser.add_argument('--managed-theme', type=Path, required=True)
    args = parser.parse_args()
    try:
        configure(args.home, json.loads(args.managed_theme.read_text()))
    except (OSError, UnicodeError, ValueError):
        warn('configuration update failed; existing settings were retained')
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
