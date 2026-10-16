"""Native launcher, delegation, and migration acceptance checks; no inference."""

from concurrent.futures import ThreadPoolExecutor
import copy
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import tomllib
import unittest
from unittest.mock import patch

import jsonschema

SOURCE = Path(sys.argv.pop(1)).resolve()
FIXTURES = Path(sys.argv.pop(1)).resolve()
sys.path.insert(0, str(SOURCE))
import auto
import workflow

spec = importlib.util.spec_from_file_location("merge_hooks", SOURCE / "merge-hooks.py")
merge_hooks = importlib.util.module_from_spec(spec)
spec.loader.exec_module(merge_hooks)


class Base(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        env = patch.dict(os.environ, {
            "HOME": str(self.root), "XDG_STATE_HOME": str(self.root / "state"),
            "CODEX_HOME": str(self.root / "codex"),
        }, clear=True)
        env.start()
        self.addCleanup(env.stop)

    def event(self, **fields):
        return dict({
            "hook_event_name": "PreToolUse", "tool_name": "collaborationspawn_agent",
            "session_id": "session", "turn_id": "turn", "tool_use_id": "call",
            "tool_input": {"model": "gpt-6-astra", "reasoning_effort": "xhigh", "message": "PRIVATE TASK"},
        }, **fields)

    def contract(self, name, output):
        schema = json.loads((FIXTURES / f"{name}.command.output.schema.json").read_text())
        jsonschema.validate(output, schema)

    def command(self, *arguments, mode="launch", enabled=False, payload=""):
        return subprocess.run(
            [sys.executable, "-I", str(SOURCE / "auto.py"), mode,
             *(["/unused-native"] if mode == "launch" else []), *arguments],
            input=payload, text=True, capture_output=True, timeout=5,
            env=dict(os.environ, CODEX_AUTO_ENABLED="1" if enabled else "0"),
        )


class GuardTests(Base):
    def test_session_context_uses_native_workflow_without_state(self):
        result = workflow.handle(self.event(hook_event_name="SessionStart"))
        self.contract("session-start", result)
        self.assertIn("Native codex-auto", result["hookSpecificOutput"]["additionalContext"])
        self.assertFalse(workflow.state_root().exists())

    def test_four_spawns_replay_and_new_turn_or_session(self):
        event = self.event()
        original = copy.deepcopy(event)
        for call in range(4):
            self.assertEqual(workflow.handle(dict(event, tool_use_id=str(call))), {})
        self.assertEqual(workflow.handle(dict(event, tool_use_id="0")), {})
        result = workflow.handle(dict(event, tool_use_id="fifth"))
        self.contract("pre-tool-use", result)
        self.assertEqual(result["hookSpecificOutput"]["permissionDecision"], "deny")
        self.assertEqual(workflow.handle(dict(event, turn_id="new")), {})
        self.assertEqual(workflow.handle(dict(event, session_id="other")), {})
        self.assertEqual(event, original)
        for path in workflow.state_root().glob("*.json"):
            self.assertNotIn("PRIVATE", path.read_text())
            self.assertNotIn("gpt-6", path.read_text())
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)

    def test_concurrent_calls_share_the_budget(self):
        with ThreadPoolExecutor(max_workers=4) as pool:
            results = list(pool.map(lambda n: workflow.handle(self.event(tool_use_id=str(n))), range(12)))
        self.assertEqual(results.count({}), 4)
        with ThreadPoolExecutor(max_workers=4) as pool:
            replay = list(pool.map(lambda _: workflow.handle(self.event(turn_id="replay")), range(12)))
        self.assertEqual(replay, [{}] * 12)
        path = workflow.state_root() / (workflow.key("session\0replay") + ".json")
        self.assertEqual(len(json.loads(path.read_text())), 1)

    def test_nested_missing_identifiers_and_broken_state_deny_only_spawn(self):
        for field in ("session_id", "turn_id", "tool_use_id"):
            for value in (None, "", 1, "x" * 201):
                result = workflow.handle(self.event(**{field: value}))
                self.assertEqual(result["hookSpecificOutput"]["permissionDecision"], "deny")
        self.assertEqual(workflow.handle(self.event(agent_id="child"))["hookSpecificOutput"]["permissionDecision"], "deny")
        self.assertFalse(workflow.state_root().exists())
        workflow.handle(self.event())
        path = next(workflow.state_root().glob("*.json"))
        for data in ('{"broken": true}', "[", "x" * 2048):
            path.write_text(data)
            self.assertEqual(workflow.handle(self.event())["hookSpecificOutput"]["permissionDecision"], "deny")
            self.assertEqual(workflow.handle(self.event(tool_name="Bash")), {})
            self.assertEqual(workflow.handle(self.event(hook_event_name="PermissionRequest")), {})

    def test_state_symlink_does_not_modify_target(self):
        workflow.private_directory(workflow.state_root())
        target = self.root / "private-file"
        target.write_text("untouched")
        path = workflow.state_root() / (workflow.key("session\0turn") + ".json")
        path.symlink_to(target)
        self.assertEqual(workflow.handle(self.event())["hookSpecificOutput"]["permissionDecision"], "deny")
        self.assertEqual(target.read_text(), "untouched")

    def test_hook_is_inert_unless_opted_in_and_rejects_malformed_input(self):
        result = self.command(mode="hook", payload="invalid")
        self.assertEqual((result.returncode, result.stdout.strip()), (0, "{}"))
        result = self.command(mode="hook", enabled=True, payload=json.dumps(self.event()))
        self.assertEqual((result.returncode, result.stdout.strip()), (0, "{}"))
        for payload in ("PRIVATE malformed", "x" * 262145):
            result = self.command(mode="hook", enabled=True, payload=payload)
            self.assertEqual(result.returncode, 2)
            self.assertNotIn("PRIVATE", result.stderr)


class LauncherTests(Base):
    def test_local_launch_preserves_arguments_and_ordinary_fallback(self):
        cases = [
            [], ["resume", "--last"], ["fork", "saved"],
            ["--model", "gpt-6-astra", "-c", 'model_reasoning_effort="xhigh"', "task"],
            ["-mchosen", "-cmodel_reasoning_effort=high", "--profile", "custom", "task"],
            ["--sandbox", "workspace-write", "--ask-for-approval", "on-request", "task"],
            ["--image", "first.png", "second.png"], ["--", "--no-daemon"],
            ["--no-daemon", "resume"], ["-C", "exec", "task"],
        ]
        for arguments in cases:
            with self.subTest(arguments=arguments), patch.object(auto, "launch_interactive", return_value=17) as launch:
                with patch.dict(os.environ, {"CODEX_CLEF_ENABLED": "1", "CODEX_CLEF_ROUTING_MODE": "apply"}):
                    self.assertEqual(auto.launch("/native", arguments), 17)
                actual = launch.call_args
                explicit = arguments[:1] == ["--no-daemon"]
                self.assertEqual(actual.args[1], ["/native", *([] if explicit else ["--no-daemon"]), *arguments])
                self.assertEqual(actual.args[2]["CODEX_AUTO_ENABLED"], "1")
                self.assertNotIn("CODEX_CLEF_ENABLED", actual.args[2])
                fallback = actual.kwargs["fallback"]
                if explicit:
                    self.assertIsNone(fallback)
                else:
                    self.assertEqual(fallback[0], ["/native", *arguments])
                    self.assertEqual(fallback[1]["CODEX_AUTO_ENABLED"], "0")
                    self.assertNotIn("CODEX_CLEF_ENABLED", fallback[1])

    def test_noninteractive_and_remote_passthrough_cannot_inherit_assisted_hooks(self):
        for arguments in (["exec", "task"], ["review"], ["app-server"], ["--version"],
                          ["--remote", "ws://example", "resume"], ["--remote=ws://example", "resume"]):
            with self.subTest(arguments=arguments), patch.object(os, "execvpe", side_effect=SystemExit) as execute:
                with patch.dict(os.environ, {"CODEX_AUTO_ENABLED": "1", "CODEX_CLEF_ENABLED": "1"}), self.assertRaises(SystemExit):
                    auto.launch("/native", arguments)
                self.assertEqual(execute.call_args.args[:2], ("/native", ["/native", *arguments]))
                self.assertNotIn("CODEX_AUTO_ENABLED", execute.call_args.args[2])
                self.assertNotIn("CODEX_CLEF_ENABLED", execute.call_args.args[2])

    def test_status_help_and_retired_commands_are_offline(self):
        history = self.root / "state/codex-clef/decisions.jsonl"
        history.parent.mkdir(parents=True)
        history.write_text("historical records\n")
        for arguments in ([], ["--json"]):
            result = self.command("status", *arguments)
            self.assertEqual(result.returncode, 0, result.stderr)
            if arguments:
                status = json.loads(result.stdout)
                self.assertEqual(status["model_selection"], "native")
                self.assertFalse(status["automatic_provider_calls"])
        self.assertEqual(self.command("--help").returncode, 0)
        for arguments in (["clef", "catalog"], ["--mode", "apply"], ["--brief-file=x"], ["--acknowledge-upload"]):
            result = self.command(*arguments)
            self.assertEqual(result.returncode, 2)
            self.assertIn("retired", result.stderr)
        self.assertFalse(workflow.state_root().exists())
        self.assertEqual(history.read_text(), "historical records\n")

    def test_wrapper_delimiter_preserves_reserved_task_words_and_native_help(self):
        for arguments in (["status"], ["clef"], ["--help"], ["--", "--mode"]):
            with patch.object(sys, "argv", ["auto.py", "launch", "/native", "--", *arguments]), patch.object(auto, "launch", return_value=0) as launch:
                self.assertEqual(auto.main(), 0)
                launch.assert_called_once_with("/native", arguments)


class MigrationTests(Base):
    def test_mixed_owned_hooks_replaced_once_and_user_hooks_preserved(self):
        root = "/nix/store/" + "a" * 32
        owned = [root + "-codex-clef/bin/codex-clef hook", root + "-codex-clef/libexec/codex-auto-hook", root + "-codex-auto/libexec/codex-auto-hook"]
        handler = lambda command: {"type": "command", "command": command}
        current = {"description": "mine", "hooks": {event: [{"hooks": [*[handler(c) for c in owned], handler("user-" + event)]}] for event in ("Stop", "PostToolUse", "PermissionRequest", "UserPromptSubmit", "SessionStart", "PreToolUse")}}
        original = copy.deepcopy(current)
        seed = {"hooks": {event: [{"hooks": [handler(owned[-1])]}] for event in ("SessionStart", "PreToolUse")}}
        merged = merge_hooks.merge(seed, current)
        self.assertEqual(current, original)
        self.assertEqual(merge_hooks.merge(seed, merged), merged)
        for event, groups in merged["hooks"].items():
            commands = [h["command"] for g in groups for h in g["hooks"]]
            self.assertEqual(commands, ["user-" + event] + ([owned[-1]] if event in seed["hooks"] else []))
        disabled = merge_hooks.merge({"hooks": {}}, merged)
        for event, groups in disabled["hooks"].items():
            self.assertEqual([h["command"] for g in groups for h in g["hooks"]], ["user-" + event])

    def test_malformed_configuration_is_not_overwritten(self):
        seed, target = self.root / "seed.json", self.root / "hooks.json"
        seed.write_text('{"hooks": {}}')
        original = '{"hooks":{"Stop":42}}'
        target.write_text(original)
        result = subprocess.run([sys.executable, str(SOURCE / "merge-hooks.py"), str(seed), str(target)], capture_output=True, timeout=5)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(target.read_text(), original)

    def test_roles_allow_explicit_native_selection(self):
        for path in (SOURCE / "agents").glob("*.toml"):
            role = tomllib.loads(path.read_text())
            self.assertNotIn("model", role)
            self.assertNotIn("model_reasoning_effort", role)
            if path.stem != "worker":
                self.assertEqual(role["sandbox_mode"], "read-only")


if __name__ == "__main__":
    unittest.main()
