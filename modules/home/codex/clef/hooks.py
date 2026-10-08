"""Native Codex lifecycle adapters; unknown or incomplete inputs abstain."""

import os
from pathlib import Path
import re
import shlex

from . import catalog
from .client import ClefError, credentials
from .routing import Decisions, signals
from .state import session_key

READ_ONLY_ROLES = {
    "explorer",
    "researcher",
    "architect",
    "security-reviewer",
    "plan-reviewer",
}
ROLES = READ_ONLY_ROLES | {"worker"}


def context(event: str, message: str) -> dict:
    return {
        "hookSpecificOutput": {"hookEventName": event, "additionalContext": message}
    }


def command_input(event: dict) -> str:
    value = event.get("tool_input", {})
    return value.get("command", "") if isinstance(value, dict) else ""


def tool_outcome(event: dict) -> tuple[bool | None, bool]:
    """Read explicit exit status, not words such as 'success' in tool output."""
    response = event.get("tool_response")
    if isinstance(response, dict):
        code = response.get("exit_code")
        if type(code) is int:
            return code == 0, True
        if response.get("isError") is True:
            return False, True
    return None, False


def check_command(command: str) -> bool:
    try:
        argv = shlex.split(command)
    except ValueError:
        return False
    if not argv or re.search(r"[;&|<>`$\n]", command):
        return False
    tool = Path(argv[0]).name
    return (
        (tool in {"go", "cargo", "npm", "pnpm"} and argv[1:2] == ["test"])
        or (
            tool == "nix"
            and (
                argv[1:3] == ["flake", "check"]
                or (
                    argv[1:2] == ["build"]
                    and any("#checks." in arg for arg in argv[2:])
                )
            )
        )
        or (tool == "nixos-rebuild" and argv[1:2] == ["dry-build"])
    )


class Hooks:
    def __init__(self, decisions: Decisions):
        self.d = decisions
        self.policy, self.store = decisions.policy, decisions.store

    def handle(self, event: dict) -> dict:
        if not isinstance(event, dict) or not isinstance(event.get("session_id"), str):
            raise ClefError("invalid_hook_input")
        name = event.get("hook_event_name")
        session = event["session_id"]
        if event.get("agent_id"):
            if not isinstance(event["agent_id"], str) or len(event["agent_id"]) > 100:
                raise ClefError("invalid_agent_id")
            event = dict(event, session_id=session + "/" + event["agent_id"])
            session = event["session_id"]
        if not session or len(session) > 200:
            raise ClefError("invalid_session")
        self.d.last_failure = None
        try:
            output = self.dispatch(event)
        except ClefError as error:
            self.d.last_failure = str(error)
            output = {}
        if self.d.last_failure:
            with self.store.counters(session) as data:
                warned = data.setdefault("warned_failures", [])
                if self.d.last_failure not in warned:
                    warned.append(self.d.last_failure)
                    output["systemMessage"] = (
                        f"Clef unavailable ({self.d.last_failure}); continuing with normal Codex behavior. "
                        "Run codex-auto status for local diagnostics."
                    )
        return output

    def dispatch(self, event: dict) -> dict:
        name, session = event["hook_event_name"], event["session_id"]
        if name == "SessionStart":
            try:
                credentials()
            except ClefError as error:
                self.d.last_failure = str(error)
            self.store.log(
                event="session",
                session=session_key(session),
                status="started",
                mode=os.environ.get("CODEX_CLEF_ROUTING_MODE", "shadow"),
                applied=False,
            )
            return context(
                name,
                "Clef-assisted session. Keep small or sequential tasks in the main session. "
                "For substantial independent work, use at most two task agents plus one focused reviewer; these are ceilings, not targets. "
                "Use architect before consequential design changes, after two genuinely failed approaches, and for substantial final diffs. "
                "Reuse the reviewer for necessary follow-up and review subsequent changes rather than repeating the full review. "
                "Give independent agents compact objectives, paths, constraints, file ownership and acceptance checks with fork_turns=none when sufficient. "
                "Give concurrent workers separate worktrees and disjoint files; the lead integrates and validates the combined result. "
                "Keep exploration read-only. For independent assignments choose native model and effort explicitly: Luna/high for bounded coding and focused lookup, Sol 6.1/medium for broad or ambiguous work and Nix activation/module wiring or Nix/store/USB contracts, Sol 6.1/high for architecture, plan and security review. Reserve Astra/low initially for the hardest architecture or unresolved failures. Manual choices win. Return to the lead after one failed repair or expanded scope. Clef shadow advice does not change the native pair. "
                "No more than four delegated tasks per user turn; no nested delegation. "
                "Routing advice never expands permissions, substitutes for tests, or authorizes publishing. "
                "Clef receives coarse metadata by default, not prompts, source code or transcripts.",
            )
        if name == "UserPromptSubmit":
            return self.workflow(event)
        if name == "PreToolUse" and event.get("tool_name") in (
            "spawn_agent",
            "Agent",
            "collaborationspawn_agent",
        ):
            return self.spawn(event)
        if name == "PostToolUse":
            return self.observe(event)
        return {}

    def workflow(self, event: dict) -> dict:
        session, turn = event["session_id"], session_key(str(event.get("turn_id", "")))
        hints = signals(event.get("prompt", ""))
        with self.store.counters(session) as data:
            if data.get("turn") != turn:
                data.update(
                    turn=turn,
                    delegations=0,
                    failed_commands=0,
                    checks_passed=0,
                    checks_failed=0,
                    failure_signals=0,
                    edits=0,
                    escalation_sent=False,
                    signals=hints,
                )
        return {}

    def spawn(self, event: dict) -> dict:
        arguments = event.get("tool_input")
        if not isinstance(arguments, dict):
            return {}
        if event.get("agent_id"):
            return {
                "hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "permissionDecision": "deny",
                    "permissionDecisionReason": "Nested delegation is disabled for Clef-assisted sessions.",
                }
            }
        role = arguments.get("agent_type")
        with self.store.counters(event["session_id"]) as data:
            data["delegations"] = data.get("delegations", 0) + 1
            if data["delegations"] > self.policy["max_delegations"]:
                return {
                    "hookSpecificOutput": {
                        "hookEventName": "PreToolUse",
                        "permissionDecision": "deny",
                        "permissionDecisionReason": "Delegation budget reached; continue in the main agent.",
                    }
                }
        if role not in ROLES:
            return {}
        shadow = os.environ.get("CODEX_CLEF_ROUTING_MODE", "shadow") == "shadow"
        # Apply mode preserves explicit choices; shadow mode only observes them.
        if not shadow and (
            arguments.get("model") is not None
            or arguments.get("reasoning_effort") is not None
        ):
            return {}
        if arguments.get("fork_context") or arguments.get("items"):
            # A prompt-only decision would miss forked/inlined context.
            return {}
        # Native V2 defaults to inheriting all turns; route only explicit none.
        if ("task_name" in arguments or "fork_turns" in arguments) and arguments.get(
            "fork_turns", "all"
        ) != "none":
            return {}
        if (
            shadow
            and self.store.shadow_samples(self.policy)
            >= self.policy["shadow_trial_samples"]
        ):
            return {}
        candidates = catalog.cached(self.policy, self.store)
        # Only known enum values enter logs; arbitrary tool arguments stay local.
        model = arguments.get("model")
        effort = arguments.get("reasoning_effort")
        source = (
            "explicit"
            if model is not None and effort is not None
            else "fallback" if model is None and effort is None else "partial_unknown"
        )
        native = {
            "native_model": (
                model
                if isinstance(model, str) and model in self.policy["models"]
                else "unknown"
            ),
            "native_effort": (
                effort
                if isinstance(effort, str)
                and effort
                in {"none", "minimal", "low", "medium", "high", "xhigh", "max", "ultra"}
                else "unknown"
            ),
            "selection_source": source,
        }
        selected = self.d.route(
            event["session_id"],
            {
                "role": role,
                "task_signals": signals(arguments.get("message", "")),
                "read_only": role in READ_ONLY_ROLES,
            },
            candidates,
            apply=not shadow,
            trial=shadow,
            native=native,
        )
        if not selected or shadow:
            return {}
        updated = dict(arguments)
        updated.update(model=selected["model"], reasoning_effort=selected["effort"])
        return {
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "allow",
                "updatedInput": updated,
            }
        }

    def observe(self, event: dict) -> dict:
        session = event["session_id"]
        success, known = tool_outcome(event)
        with self.store.counters(session) as data:
            response = event.get("tool_response")
            if isinstance(response, str):
                # 0.161.0 Bash hooks expose output text, not an exit status.
                # Count only advisory failure signals; never infer a passed test.
                failure_hint = bool(
                    re.search(
                        r"(?im)^(?:FAIL(?:ED)?\b|error:|fatal:|Traceback|AssertionError)",
                        response,
                    )
                )
                data["failure_signals"] = data.get("failure_signals", 0) + int(
                    failure_hint
                )
            if (
                event.get("tool_name") == "apply_patch"
                and event.get("tool_response") is not None
            ):
                data["edits"] = data.get("edits", 0) + 1
            if known:
                data["failed_commands"] = (
                    0 if success else data.get("failed_commands", 0) + 1
                )
                if check_command(command_input(event)):
                    key = "checks_passed" if success else "checks_failed"
                    data[key] = data.get(key, 0) + 1
            trigger = max(
                data.get("failed_commands", 0), data.get("failure_signals", 0)
            ) >= 2 and not data.get("escalation_sent")
            if trigger:
                data["escalation_sent"] = True
        if not trigger:
            return {}
        return context(
            "PostToolUse",
            "Repeated failure signals observed; confirm the actual failures. Gather evidence before repeating the same approach. "
            "After two genuinely failed approaches, consult the architect with hypotheses and evidence.",
        )
