#!/usr/bin/env python3
"""Plan, execute and gate registry-owned CI lanes without shell-generated commands."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import urllib.error
import urllib.request


class BaselineUnavailable(Exception):
    pass


def validate_registry(registry):
    ci = registry['ci']
    registered = registry['host'] + registry['support']
    if len(registered) != len(set(registered)):
        raise ValueError('duplicate public check name')
    if set(ci['hostChecks']) != set(registry['host']):
        raise ValueError('host lane coverage differs from public host registry')
    lanes = list(ci['hostChecks'].values()) + list(ci['supportGroups'].values()) + list(ci['unitGroups'].values())
    assigned = [name for lane in lanes for name in lane]
    if len(assigned) != len(set(assigned)) or set(assigned) != set(registered):
        raise ValueError('every registered check must have exactly one CI assignment')
    for host, checks in ci['hostChecks'].items():
        if host not in checks:
            raise ValueError(f'{host} lane does not build its host')
    if not set(ci['alwaysUnitGroups']) <= set(ci['unitGroups']):
        raise ValueError('unknown mandatory unit group')
    if any(not set(hosts) <= set(registry['host']) for hosts in ci['hostCheckSources'].values()):
        raise ValueError('unknown integration source owner')
    for domain in ci['domains'].values():
        if not set(domain['support']) <= set(ci['supportGroups']) or not set(domain['units']) <= set(ci['unitGroups']) or not set(domain.get('hosts', [])) <= set(registry['host']):
            raise ValueError('unknown domain lane')


def selection(registry, paths=None, reason=None):
    validate_registry(registry)
    ci = registry['ci']
    hosts, groups, units = set(), {'registry'}, set(ci['alwaysUnitGroups'])
    reasons = []

    def full(why):
        hosts.update(registry['host'])
        groups.update(ci['supportGroups'])
        units.update(ci['unitGroups'])
        reasons.append(why)

    if paths is None:
        full(reason or 'full validation requested')
    else:
        for path in sorted(set(paths)):
            if path in {'README.md', 'AGENTS.md', 'LICENSE'} or path.startswith('docs/'):
                reasons.append(f'documentation: {path}')
                continue
            if path.startswith('.github/') or path in {'checks/default.nix', 'checks/context.nix', 'checks/registry.nix', 'checks/hosts.nix'} or path.startswith('checks/ci-'):
                full(f'CI or shared check infrastructure: {path}')
                continue
            check_path = path.removeprefix('checks/')
            domains = [domain for domain in ci['domains'].values() if any(check_path.startswith(prefix) for prefix in domain['checkPrefixes'])] if path.startswith('checks/') else []
            integration_owners = [host for host, checks in ci['hostChecks'].items() if path.startswith('checks/') and any(check_path.startswith(name) for name in checks if name != host)]
            source_owners = [host for source, owners in ci['hostCheckSources'].items() for host in owners if path.startswith('checks/') and check_path.startswith(source)]
            unit_sources = [group for group, checks in ci['unitGroups'].items() if path.startswith('checks/') and any(check_path.startswith(check) for check in checks)]
            if domains or integration_owners or source_owners or unit_sources:
                hosts.update(integration_owners + source_owners)
                units.update(unit_sources)
                for domain in domains:
                    groups.update(domain['support'])
                    units.update(domain['units'])
                if check_path.startswith('usb-'):
                    hosts.add('usb')
                reasons.append(f'check domain: {path}')
                continue
            owner = next((host for host in registry['host'] if path.startswith(f'hosts/{host}/')), None)
            if owner:
                hosts.add(owner)
                groups.update(ci['supportGroups'])
                units.update(ci['unitGroups'])
                reasons.append(f'{owner} configuration: {path}')
                continue
            matches = [(len(prefix), domain) for domain in ci['domains'].values() for prefix in domain['prefixes'] if path.startswith(prefix)]
            if matches:
                # The longest prefix makes USB scripts narrower than shared scripts.
                _, domain = max(matches, key=lambda item: item[0])
                groups.update(domain['support'])
                units.update(domain['units'])
                owner = next((host for host in registry['host'] if path in {f'modules/home/dms/{host}.nix', f'modules/home/wallpaper/{host}.nix'}), None)
                hosts.update([owner] if owner else domain.get('hosts', registry['host']))
                reasons.append(f'owned runtime domain: {path}')
                continue
            full(f'shared or unknown source: {path}')
    support_names = {name for group in groups for name in ci['supportGroups'][group]}
    unit_names = {name for group in units for name in ci['unitGroups'][group]}
    selected_hosts = [host for host in registry['host'] if host in hosts]
    return {'hosts': selected_hosts, 'support': [name for name in registry['support'] if name in support_names], 'units': [name for name in registry['support'] if name in unit_names], 'reasons': reasons or ['no runtime changes'], 'hostChecks': {host: ci['hostChecks'][host] for host in selected_hosts}}


def parse_diff(data):
    """Read git --name-status -z, including both sides of moves and copies."""
    fields = data.split(b'\0')
    if fields[-1] != b'':
        raise ValueError('diff is not NUL terminated')
    fields.pop()
    paths = []
    while fields:
        status = fields.pop(0).decode('ascii')
        count = 2 if status.startswith(('R', 'C')) else 1
        if not re.fullmatch(r'[ACDMRTUXB][0-9]*', status) or len(fields) < count:
            raise ValueError('malformed name-status diff')
        paths.extend(os.fsdecode(fields.pop(0)) for _ in range(count))
    return paths


def git(*args):
    return subprocess.check_output(['git', *args]).decode().strip()


def valid_sha(value):
    return isinstance(value, str) and bool(re.fullmatch(r'[0-9a-f]{40}', value))


def latest_successful(runs):
    return next((run['head_sha'] for run in runs if run.get('head_branch') == 'main' and run.get('status') == 'completed' and run.get('conclusion') == 'success' and valid_sha(run.get('head_sha'))), None)


def successful_main_sha():
    try:
        url = os.environ.get('GITHUB_API_URL', 'https://api.github.com') + '/repos/' + os.environ['GITHUB_REPOSITORY'] + '/actions/workflows/validate.yml/runs?branch=main&status=success&per_page=100'
        request = urllib.request.Request(url, headers={'Authorization': 'Bearer ' + os.environ['GH_TOKEN'], 'Accept': 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28'})
        with urllib.request.urlopen(request, timeout=20) as response:
            sha = latest_successful(json.load(response)['workflow_runs'])
    except (urllib.error.URLError, OSError, ValueError, KeyError) as error:
        raise BaselineUnavailable('successful main baseline lookup unavailable') from error
    if not sha:
        raise BaselineUnavailable('no successful Validate baseline on main')
    return sha


def changed_paths(event_name, event, head, main_sha=None):
    if not valid_sha(head):
        raise BaselineUnavailable('tested HEAD is not an exact commit SHA')
    if event_name == 'pull_request':
        base = event.get('pull_request', {}).get('base', {}).get('sha')
        if not valid_sha(base):
            raise BaselineUnavailable('pull request base SHA unavailable')
        try:
            base = git('merge-base', base, head)
        except subprocess.CalledProcessError as error:
            raise BaselineUnavailable('pull request merge base unavailable') from error
    elif event_name == 'push':
        base = main_sha
        if not valid_sha(base):
            raise BaselineUnavailable('successful main baseline unavailable')
        if subprocess.run(['git', 'merge-base', '--is-ancestor', base, head], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode:
            raise BaselineUnavailable('successful main baseline is not an ancestor of tested HEAD')
    else:
        raise BaselineUnavailable('scheduled or manual full validation')
    try:
        return parse_diff(subprocess.check_output(['git', 'diff', '--name-status', '-z', '--find-renames', base, head, '--']))
    except (subprocess.CalledProcessError, ValueError) as error:
        raise BaselineUnavailable('changed paths unavailable') from error


def expected_jobs(plan):
    return {'plan': True, 'source-unit': bool(plan['units'] or 'codex-clef' in plan['support']), 'support-check': bool(plan['support']), 'host-check': bool(plan['hosts'])}


def gate(expected, needs):
    failures = []
    if not isinstance(expected, dict) or set(expected) != {'plan', 'source-unit', 'support-check', 'host-check'} or any(type(required) is not bool for required in expected.values()) or not expected['plan'] or not expected['support-check']:
        return ['invalid or missing expected-job plan']
    if not isinstance(needs, dict) or set(needs) != set(expected):
        return ['job result coverage differs from expected-job plan']
    for name, required in expected.items():
        result = needs[name].get('result') if isinstance(needs[name], dict) else None
        if result == 'success' or (result == 'skipped' and not required):
            continue
        failures.append(f'{name}: {result}, expected ' + ('success' if required else 'intentional skip or success'))
    return failures


def build_checks(checks):
    if not isinstance(checks, list) or any(not isinstance(name, str) or not re.fullmatch(r'[a-z0-9-]+', name) for name in checks):
        raise ValueError('invalid selected check names')
    failures = []
    for name in checks:
        print(f'::group::{name}', flush=True)
        code = subprocess.run(['nix', 'build', '--no-link', '--print-build-logs', f'.#checks.x86_64-linux.{name}']).returncode
        print('::endgroup::', flush=True)
        if code:
            code = code if code > 0 else 128 - code
            failures.append((name, code))
            print(f'::error::{name} exited with code {code}', flush=True)
    if failures:
        print('Failed checks: ' + ', '.join(f'{name} ({code})' for name, code in failures), file=sys.stderr)
        return failures[0][1]
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['plan', 'build-support', 'build-units', 'build-host', 'gate'])
    parser.add_argument('--registry', default='ci-registry.json')
    args = parser.parse_args()
    if args.command == 'gate':
        try:
            failures = gate(json.loads(os.environ['EXPECTED_JOBS']), json.loads(os.environ['JOB_RESULTS']))
        except (KeyError, ValueError, TypeError, AttributeError):
            failures = ['missing or malformed job result JSON']
        for failure in failures:
            print(f'::error::{failure}')
        return bool(failures)
    if args.command.startswith('build-'):
        plan = json.loads(os.environ['CI_PLAN'])
        checks = plan['hostChecks'][os.environ['CI_HOST']] if args.command == 'build-host' else plan['units' if args.command == 'build-units' else 'support']
        return build_checks(checks)
    registry = json.loads(Path(args.registry).read_text())
    head = git('rev-parse', 'HEAD')
    if head != os.environ['GITHUB_SHA']:
        raise ValueError('checkout differs from pinned tested SHA')
    event = json.loads(Path(os.environ['GITHUB_EVENT_PATH']).read_text())
    event_name = os.environ['GITHUB_EVENT_NAME']
    try:
        base = successful_main_sha() if event_name == 'push' else None
        plan = selection(registry, changed_paths(event_name, event, head, base))
    except BaselineUnavailable as error:
        plan = selection(registry, reason=str(error))
    outputs = {'plan': plan, 'hosts': plan['hosts'], 'expected': expected_jobs(plan), 'tree': git('rev-parse', 'HEAD^{tree}')}
    with open(os.environ['GITHUB_OUTPUT'], 'a', encoding='utf-8') as output:
        for key, value in outputs.items():
            output.write(key + '=' + (value if isinstance(value, str) else json.dumps(value, ensure_ascii=True, separators=(',', ':'))) + '\n')
    print(json.dumps(plan, indent=2, ensure_ascii=True))
    return 0


if __name__ == '__main__':
    sys.exit(main())
