#!/usr/bin/env python3
"""Contract fixtures for selection, Git baselines, CI coverage and failure propagation."""
import copy
import contextlib
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

import ci

REGISTRY = json.loads(Path(sys.argv.pop(1)).read_text())


class SelectorTests(unittest.TestCase):
    def test_every_check_has_one_assignment_and_full_run_covers_it(self):
        ci.validate_registry(REGISTRY)
        plan = ci.selection(REGISTRY)
        assigned = plan['support'] + plan['units'] + [check for checks in plan['hostChecks'].values() for check in checks]
        self.assertCountEqual(assigned, REGISTRY['host'] + REGISTRY['support'])
        self.assertEqual(len(assigned), len(set(assigned)))
        for host in REGISTRY['host']:
            self.assertIn(host, plan['hostChecks'][host])

    def test_missing_or_duplicate_assignment_is_rejected(self):
        for mutation in ('missing', 'duplicate'):
            registry = copy.deepcopy(REGISTRY)
            if mutation == 'missing':
                registry['ci']['hostChecks']['usb'].remove('usb-update-integration')
            else:
                registry['ci']['supportGroups']['scripts'].append('usb-update-integration')
            with self.subTest(mutation=mutation), self.assertRaises(ValueError):
                ci.validate_registry(registry)

    def test_documentation_retains_cheap_global_contracts_and_empty_hosts(self):
        plan = ci.selection(REGISTRY, ['README.md', 'AGENTS.md', 'LICENSE', 'docs/design.md'])
        self.assertEqual(plan['hosts'], [])
        self.assertEqual(plan['units'], ['host-configuration-contracts'])
        self.assertEqual(plan['support'], ['ci-registry'])
        self.assertEqual(ci.expected_jobs(plan), {'plan': True, 'source-unit': True, 'support-check': True, 'host-check': False})

    def test_deployed_markdown_selects_runtime_and_clef_contracts(self):
        plan = ci.selection(REGISTRY, ['modules/home/codex/instructions.md'])
        self.assertEqual(plan['hosts'], ['desktop', 'usb', 'laptop'])
        self.assertIn('codex-clef', plan['support'])
        self.assertIn('bannerlord-codex', plan['support'])
        self.assertTrue(ci.expected_jobs(plan)['source-unit'])

    def test_host_specific_changes_select_owner(self):
        for path, host in [('hosts/laptop/default.nix', 'laptop'), ('modules/home/dms/usb.nix', 'usb'), ('modules/home/wallpaper/usb.nix', 'usb')]:
            with self.subTest(path=path):
                self.assertEqual(ci.selection(REGISTRY, [path])['hosts'], [host])

    def test_shared_runtime_and_package_changes_select_all_hosts(self):
        for path in ['flake.lock', 'flake.nix', 'hosts/common/default.nix', 'home.nix', 'modules/home/bannerlord-speech/package.nix', 'modules/home/wallpaper/wallpaper-sync.py', 'modules/home/neovim/packages.nix']:
            with self.subTest(path=path):
                self.assertEqual(ci.selection(REGISTRY, [path])['hosts'], ['desktop', 'usb', 'laptop'])

    def test_usb_script_and_integration_test_retain_usb_vm_coverage(self):
        for path, expected_hosts in [('modules/home/scripts/usb/update-usb/phases.sh', ['desktop', 'usb']), ('checks/usb-update-unit.sh', ['usb']), ('checks/usb-steam.nix', ['usb'])]:
            with self.subTest(path=path):
                plan = ci.selection(REGISTRY, [path])
                self.assertEqual(plan['hosts'], expected_hosts)
                self.assertIn('usb-update-integration', plan['hostChecks']['usb'])
                self.assertIn('usb-initrd-ordering', plan['hostChecks']['usb'])
                self.assertIn('usb-installed-environment', plan['hostChecks']['usb'])
                self.assertIn('shellcheck', plan['support'])

    def test_checks_only_select_domain_without_unrelated_hosts(self):
        plan = ci.selection(REGISTRY, ['checks/neovim-hover.lua'])
        self.assertEqual(plan['hosts'], [])
        self.assertCountEqual(plan['support'], ['neovim-langmap', 'neovim-lsp-health', 'ci-registry'])
        speech = ci.selection(REGISTRY, ['checks/bannerlord-speech.nix'])
        self.assertEqual(speech['hosts'], ['desktop'])
        self.assertCountEqual(speech['units'], ['bannerlord-speech-unit', 'host-configuration-contracts'])

    def test_installed_environment_test_changes_select_owning_host(self):
        for host in ['desktop', 'usb']:
            with self.subTest(host=host):
                plan = ci.selection(REGISTRY, [f'checks/{host}-installed-environment.nix'])
                self.assertEqual(plan['hosts'], [host])
                self.assertIn(f'{host}-installed-environment', plan['hostChecks'][host])
                self.assertIn('ci-registry', plan['support'])
                self.assertNotIn('codex-clef', plan['support'])

    def test_combined_installed_environment_source_selects_desktop_and_usb(self):
        plan = ci.selection(REGISTRY, ['checks/installed-environment.nix'])
        self.assertEqual(plan['hosts'], ['desktop', 'usb'])
        self.assertEqual(plan['support'], ['ci-registry'])

    def test_configuration_contract_source_is_always_lightweight(self):
        plan = ci.selection(REGISTRY, ['checks/host-configuration-contracts.nix'])
        self.assertEqual(plan['hosts'], [])
        self.assertEqual(plan['units'], ['host-configuration-contracts'])
        self.assertEqual(plan['support'], ['ci-registry'])

    def test_unknown_ci_and_shared_check_files_have_full_coverage(self):
        for path in ['unknown.md', 'checks/context.nix', 'checks/default.nix', '.github/workflows/validate.yml', '.github/scripts/ci.py', 'checks/ci-registry.nix']:
            with self.subTest(path=path):
                plan = ci.selection(REGISTRY, [path])
                self.assertEqual(plan['hosts'], ['desktop', 'usb', 'laptop'])
                self.assertIn('bannerlord-speech-unit', plan['units'])
                self.assertIn('codex-clef', plan['support'])

    def test_diff_parser_retains_deleted_and_both_renamed_paths(self):
        paths = ci.parse_diff(b'D\0modules/home/bannerlord-speech/engine.py\0R100\0modules/home/codex/instructions.md\0docs/new\nname.md\0')
        self.assertEqual(paths, ['modules/home/bannerlord-speech/engine.py', 'modules/home/codex/instructions.md', 'docs/new\nname.md'])
        plan = ci.selection(REGISTRY, paths)
        self.assertEqual(plan['hosts'], ['desktop', 'usb', 'laptop'])
        self.assertIn('bannerlord-speech-unit', plan['units'])
        self.assertIn('codex-clef', plan['support'])
        with self.assertRaises(ValueError):
            ci.parse_diff(b'R100\0missing-second-path\0')


class GitFixtureTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.previous_cwd = os.getcwd()
        os.chdir(self.temp.name)
        self.command('init', '-q', '-b', 'main')
        self.command('config', 'user.email', 'ci@example.invalid')
        self.command('config', 'user.name', 'CI fixture')
        self.write('README.md', 'initial')
        self.base = self.commit()

    def tearDown(self):
        os.chdir(self.previous_cwd)
        self.temp.cleanup()

    def command(self, *args):
        return subprocess.check_output(['git', *args], stderr=subprocess.DEVNULL).decode().strip()

    def write(self, path, contents):
        Path(path).parent.mkdir(parents=True, exist_ok=True)
        Path(path).write_text(contents)

    def commit(self):
        self.command('add', '-A')
        self.command('commit', '-qm', 'fixture')
        return self.command('rev-parse', 'HEAD')

    def test_cancelled_a_remains_in_next_b_diff(self):
        self.write('modules/home/codex/instructions.md', 'deployed prompt')
        cancelled = self.commit()
        self.write('README.md', 'docs B')
        head = self.commit()
        runs = [{'head_sha': cancelled, 'head_branch': 'main', 'status': 'completed', 'conclusion': 'cancelled'}, {'head_sha': self.base, 'head_branch': 'main', 'status': 'completed', 'conclusion': 'success'}]
        baseline = ci.latest_successful(runs)
        self.assertEqual(baseline, self.base)
        paths = ci.changed_paths('push', {}, head, baseline)
        self.assertIn('modules/home/codex/instructions.md', paths)
        self.assertIn('codex-clef', ci.selection(REGISTRY, paths)['support'])

    def test_pr_uses_pinned_base_and_tested_merge(self):
        self.command('checkout', '-qb', 'feature')
        self.write('modules/home/scripts/usb/fixture.sh', 'echo fixture')
        self.commit()
        self.command('checkout', '-q', 'main')
        self.write('README.md', 'main advanced')
        pinned = self.commit()
        self.command('merge', '-q', '--no-ff', 'feature', '-m', 'tested merge')
        tested = self.command('rev-parse', 'HEAD')
        paths = ci.changed_paths('pull_request', {'pull_request': {'base': {'sha': pinned}}}, tested)
        self.assertEqual(paths, ['modules/home/scripts/usb/fixture.sh'])

    def test_deleted_runtime_and_rename_into_docs_still_select_runtime(self):
        self.write('modules/home/codex/instructions.md', 'same contents')
        self.write('modules/home/bannerlord-speech/engine.py', 'service')
        base = self.commit()
        Path('docs').mkdir()
        self.command('mv', 'modules/home/codex/instructions.md', 'docs/old-prompt.md')
        Path('modules/home/bannerlord-speech/engine.py').unlink()
        head = self.commit()
        paths = ci.changed_paths('push', {}, head, base)
        self.assertCountEqual(paths, ['modules/home/codex/instructions.md', 'docs/old-prompt.md', 'modules/home/bannerlord-speech/engine.py'])
        self.assertIn('codex-clef', ci.selection(REGISTRY, paths)['support'])

    def test_missing_and_nonancestor_baselines_fall_back_to_full(self):
        for event, data, baseline in [('push', {}, None), ('push', {}, 'f' * 40), ('pull_request', {'pull_request': {'base': {}}}, None), ('schedule', {}, None), ('workflow_dispatch', {}, None)]:
            with self.subTest(event=event, baseline=baseline), self.assertRaises(ci.BaselineUnavailable):
                ci.changed_paths(event, data, self.base, baseline)
        self.command('checkout', '-q', '--orphan', 'unrelated')
        self.command('rm', '-q', '-rf', '.')
        self.write('other.txt', 'unrelated')
        unrelated = self.commit()
        with self.assertRaises(ci.BaselineUnavailable):
            ci.changed_paths('push', {}, unrelated, self.base)
        self.assertEqual(ci.selection(REGISTRY, reason='baseline unavailable')['hosts'], ['desktop', 'usb', 'laptop'])

    def test_first_workflow_edit_gets_full_validation(self):
        self.write('.github/workflows/validate.yml', 'name: candidate workflow')
        head = self.commit()
        paths = ci.changed_paths('push', {}, head, self.base)
        plan = ci.selection(REGISTRY, paths)
        self.assertEqual(plan['hosts'], ['desktop', 'usb', 'laptop'])
        self.assertIn('bannerlord-speech-unit', plan['units'])
        self.assertIn('codex-clef', plan['support'])

    def test_api_unavailability_is_a_full_baseline_fallback(self):
        with patch.dict(os.environ, {'GH_TOKEN': 'test-only', 'GITHUB_REPOSITORY': 'owner/repo'}), patch.object(ci.urllib.request, 'urlopen', side_effect=ci.urllib.error.URLError('unavailable')):
            with self.assertRaises(ci.BaselineUnavailable):
                ci.successful_main_sha()
        self.assertIsNone(ci.latest_successful([{'head_branch': 'main', 'head_sha': self.base, 'status': 'completed', 'conclusion': 'cancelled'}]))

    def test_checkout_must_match_exact_tested_sha(self):
        Path('registry.json').write_text(json.dumps(REGISTRY))
        with patch.dict(os.environ, {'GITHUB_SHA': 'f' * 40}), patch.object(sys, 'argv', ['ci.py', 'plan', '--registry', 'registry.json']):
            with self.assertRaisesRegex(ValueError, 'pinned tested SHA'):
                ci.main()

    def test_output_json_does_not_interpret_untrusted_path_content(self):
        self.write('docs/quote\n$(touch SHOULD_NOT_EXIST).md', 'documentation')
        head = self.commit()
        event_file, output_file, registry_file = Path('event.json'), Path('output.txt'), Path('registry.json')
        event_file.write_text('{}')
        registry_file.write_text(json.dumps(REGISTRY))
        env = {'GITHUB_SHA': head, 'GITHUB_EVENT_NAME': 'push', 'GITHUB_EVENT_PATH': str(event_file), 'GITHUB_OUTPUT': str(output_file)}
        with patch.dict(os.environ, env), patch.object(sys, 'argv', ['ci.py', 'plan', '--registry', str(registry_file)]), patch.object(ci, 'successful_main_sha', return_value=self.base), contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(ci.main(), 0)
        outputs = dict(line.split('=', 1) for line in output_file.read_text().splitlines())
        self.assertEqual(set(outputs), {'plan', 'hosts', 'expected', 'tree'})
        self.assertEqual(json.loads(outputs['hosts']), [])
        self.assertFalse(Path('SHOULD_NOT_EXIST').exists())
        self.assertEqual(outputs['tree'], self.command('rev-parse', 'HEAD^{tree}'))


class GateTests(unittest.TestCase):
    def test_all_selected_success_is_required(self):
        expected = ci.expected_jobs(ci.selection(REGISTRY))
        needs = {name: {'result': 'success'} for name in expected}
        self.assertEqual(ci.gate(expected, needs), [])
        for status in ['failure', 'cancelled', 'skipped', 'unknown']:
            for name in expected:
                with self.subTest(status=status, job=name):
                    candidate = copy.deepcopy(needs)
                    candidate[name]['result'] = status
                    self.assertTrue(ci.gate(expected, candidate))

    def test_only_intentionally_empty_lanes_may_skip(self):
        expected = ci.expected_jobs(ci.selection(REGISTRY, ['README.md']))
        needs = {'plan': {'result': 'success'}, 'source-unit': {'result': 'success'}, 'support-check': {'result': 'success'}, 'host-check': {'result': 'skipped'}}
        self.assertEqual(ci.gate(expected, needs), [])
        needs['support-check']['result'] = 'skipped'
        self.assertTrue(ci.gate(expected, needs))
        needs['source-unit']['result'] = 'cancelled'
        self.assertTrue(ci.gate(expected, needs))

    def test_missing_malformed_and_incomplete_expected_json_fail(self):
        for expected in [None, {}, {'plan': False}, {'plan': 'true'}]:
            with self.subTest(expected=expected):
                self.assertTrue(ci.gate(expected, {}))
        expected = ci.expected_jobs(ci.selection(REGISTRY))
        self.assertTrue(ci.gate(expected, {}))

    def test_builds_continue_after_failures_and_preserve_exact_exit_code(self):
        with patch.object(ci.subprocess, 'run', side_effect=[subprocess.CompletedProcess([], 42), subprocess.CompletedProcess([], 0), subprocess.CompletedProcess([], 7)]) as run, contextlib.redirect_stdout(io.StringIO()) as stdout, contextlib.redirect_stderr(io.StringIO()) as stderr:
            self.assertEqual(ci.build_checks(['first', 'second', 'third']), 42)
        self.assertEqual(run.call_count, 3)
        self.assertIn('first exited with code 42', stdout.getvalue())
        self.assertIn('third (7)', stderr.getvalue())
        self.assertEqual(run.call_args_list[1].args[0][-1], '.#checks.x86_64-linux.second')


if __name__ == '__main__':
    unittest.main(verbosity=2)
