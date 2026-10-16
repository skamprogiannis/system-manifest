"""Opt into native Codex delegation without a routing service."""

import json
import os
from pathlib import Path
import sys

# The packaged entrypoint runs with -I; import only its immutable sibling files.
sys.path.insert(0, str(Path(__file__).resolve().parent))
from startup import launch_context, launch_interactive
from workflow import MAX_DELEGATIONS, handle, state_root


def status():
    return {
        "assisted_environment": os.environ.get("CODEX_AUTO_ENABLED") == "1",
        "model_selection": "native",
        "model_and_effort_overrides": False,
        "automatic_provider_calls": False,
        "approval_and_sandbox_settings": "native_configuration",
        "max_delegations_per_turn": MAX_DELEGATIONS,
        "nested_delegation": False,
        "state_directory": str(state_root()),
    }


def launch(binary, arguments):
    context = launch_context(arguments)
    env = dict(os.environ)
    # Retired hooks can remain loaded in an old client until it is restarted.
    env.pop("CODEX_CLEF_ENABLED", None)
    env.pop("CODEX_CLEF_ROUTING_MODE", None)
    env.pop("CODEX_AUTO_ENABLED", None)
    if not context.interactive:
        os.execvpe(binary, [binary, *arguments], env)
    env["CODEX_AUTO_ENABLED"] = "1"
    fallback = None
    if not context.no_daemon:
        fallback = ([binary, *arguments], dict(env, CODEX_AUTO_ENABLED="0"))
    return launch_interactive(
        binary,
        [binary, *([] if context.no_daemon else ["--no-daemon"]), *arguments],
        env,
        fallback=fallback,
    )


def main():
    mode, *arguments = sys.argv[1:]
    if mode == "hook":
        if os.environ.get("CODEX_AUTO_ENABLED") != "1":
            print("{}")
            return 0
        raw = sys.stdin.buffer.read(262145)
        try:
            if len(raw) > 262144:
                raise ValueError("hook input too large")
            result = handle(json.loads(raw))
        except (ValueError, UnicodeError):
            # Exit 2 blocks a PreToolUse hook when its input cannot be checked.
            print("codex-auto: invalid hook input; delegation could not be checked", file=sys.stderr)
            return 2
        print(json.dumps(result))
        return 0
    binary, *arguments = arguments
    if arguments[:1] in (["--help"], ["-h"]):
        print(
            "usage: codex-auto [--] [CODEX_OPTIONS] [TASK_OR_SUBCOMMAND]\n"
            "       codex-auto status [--json]\n\n"
            "Launch native Codex with bounded delegation. Model, effort, speed, "
            "approval and sandbox settings remain native.\n"
            "Use -- before a literal status/clef prompt or --help for native help.\n"
            "Clef routing and evaluation commands have been retired."
        )
        return 0
    if arguments[:1] == ["status"]:
        if arguments[1:] not in ([], ["--json"]):
            print("usage: codex-auto status [--json]", file=sys.stderr)
            return 2
        info = status()
        if arguments[1:]:
            print(json.dumps(info, indent=2))
        else:
            print(
                "Codex Auto — native assisted workflow\n"
                "Model, effort and speed: native configured, saved or explicit choices\n"
                "Approvals and sandbox: native configuration\n"
                f"Assisted environment: {'enabled' if info['assisted_environment'] else 'not enabled in this process'}\n"
                f"Delegation guard: {MAX_DELEGATIONS} tasks per turn; no nested delegation\n"
                "Automatic provider calls: none; Clef retired\n"
                f"Local guard state: {info['state_directory']}\n"
                "Offline status; does not inspect the active model, account usage or hook installation."
            )
        return 0
    if arguments[:1] == ["clef"] or (arguments and arguments[0].split("=", 1)[0] in {
        "--mode", "--brief-file", "--acknowledge-upload",
    }):
        print("codex-auto: Clef options and operations were retired; use codex-auto --help", file=sys.stderr)
        return 2
    if arguments[:1] == ["--"]:
        arguments = arguments[1:]
    return launch(binary, arguments)


if __name__ == "__main__":
    raise SystemExit(main())
