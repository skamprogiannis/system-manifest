"""Native Codex lifecycle adapters; unknown or incomplete inputs abstain."""

import os
import json
from pathlib import Path
import re
import shlex

from . import catalog
from .client import ClefError, credentials, question
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
WORKFLOW_CHECKS = {
    "unit": "Prioritize focused unit/integration tests around changed behavior.",
    "config": "Prioritize configuration evaluation and targeted Nix checks, then the required desktop dry-build.",
    "security": "Prioritize security checks and an independent review of sensitive changes.",
    "browser": "Prioritize browser-based verification of affected UI behavior.",
    "none": "No additional check prioritization is useful yet.",
}


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
                mode=os.environ.get("CODEX_CLEF_ROUTING_MODE", "apply"),
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
                "Keep exploration read-only. Do not provide model/effort on spawn_agent unless the user explicitly overrides routing. "
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
        if name in ("Stop", "SubagentStop"):
            return self.stop(event)
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
                    stop_count=0,
                    escalation_sent=False,
                    signals=hints,
                )
        result = self.d.ask(
            "workflow",
            session,
            {"task_signals": hints},
            {
                "skill": question(
                    "Select the most relevant installed workflow skill from coarse task signals; choose none when uncertain.",
                    self.policy["skills"],
                ),
                "check": question(
                    "Prioritize checks; this never excuses skipping required repository checks.",
                    WORKFLOW_CHECKS,
                ),
            },
        )
        if result is None:
            return {}
        messages = []
        skill = result.answers["skill"]
        if skill.choice != "none" and skill.probability >= 0.75:
            messages.append(f"Consider the installed {skill.choice} skill.")
        check = result.answers["check"]
        if check.choice != "none" and check.probability >= 0.75:
            messages.append(WORKFLOW_CHECKS[check.choice])
        if hints["architecture"] and (
            hints["security"] or hints["system"] or hints["substantial"]
        ):
            messages.append(
                "Obtain a bounded read-only architect consultation before implementation; preserve the interactive plan-reviewer for user-led design discussion."
            )
        return context("UserPromptSubmit", " ".join(messages)) if messages else {}

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
        # Explicit choices are authoritative, including a partial effort override.
        if (
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
        candidates = catalog.cached(self.policy, self.store)
        selected = self.d.route(
            event["session_id"],
            {
                "role": role,
                "task_signals": signals(arguments.get("message", "")),
                "read_only": role in READ_ONLY_ROLES,
            },
            candidates,
            apply=os.environ.get("CODEX_CLEF_ROUTING_MODE") != "shadow",
        )
        if not selected or os.environ.get("CODEX_CLEF_ROUTING_MODE") == "shadow":
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
                # 0.160.0 Bash hooks expose output text, not an exit status.
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
            state = {
                key: data.get(key, 0)
                for key in (
                    "failed_commands",
                    "failure_signals",
                    "checks_passed",
                    "checks_failed",
                    "edits",
                )
            }
        if not trigger:
            return {}
        result = self.d.ask(
            "escalation",
            session,
            state,
            {
                "next": question(
                    "Select a useful next step after repeated command failures. Failure signals from output text are not verified exit statuses or necessarily distinct failed hypotheses.",
                    {
                        "context": "Inspect the error and gather missing evidence before retrying.",
                        "architect": "Consult the read-only architect with failed hypotheses and relevant evidence.",
                        "continue": "Continue the current approach, but change the failing step.",
                    },
                )
            },
        )
        if result is None:
            return context(
                "PostToolUse",
                "Repeated failure signals observed; confirm the actual failures. Gather evidence before repeating the same approach.",
            )
        messages = {
            "context": "Gather missing evidence and inspect the failure before retrying.",
            "architect": "Consider a bounded architect consultation; provide the actual failed hypotheses and evidence, not just a failure count.",
            "continue": "Change the failing step rather than blindly rerunning it.",
        }
        return context("PostToolUse", messages[result.answers["next"].choice])

    def stop(self, event: dict) -> dict:
        session = event["session_id"]
        if event.get("stop_hook_active"):
            return {}
        with self.store.counters(session) as data:
            state = {
                key: data.get(key, 0)
                for key in ("edits", "checks_passed", "checks_failed")
            }
            state["task_signals"] = data.get("signals", {})
            if (
                not state["edits"]
                or data.get("stop_count", 0) >= self.policy["max_stop_continuations"]
            ):
                return {}
            data["stop_count"] = data.get("stop_count", 0) + 1
        # The last message stays local. This is a narrow evidence signal, not a code review.
        message = event.get("last_assistant_message") or ""
        state["claims_completion"] = bool(
            re.search(r"\b(done|complete|fixed|passed|implemented)\b", message, re.I)
        )
        state["discloses_limitation"] = bool(
            re.search(
                r"\b(unverified|blocked|unable|not run|could not|failed)\b",
                message,
                re.I,
            )
        )
        result = self.d.ask(
            "completion",
            session,
            state,
            {
                "completion": question(
                    "Does the available metadata justify an additional verification pass? Passing commands do not prove correctness, "
                    "and absence of a recorded test is not proof that no tests ran. Do not overrule an honest limitation report.",
                    {
                        "finish": "No additional pass is justified from this evidence.",
                        "verify": "Request one focused verification or disclosure pass.",
                        "review": "Suggest an independent read-only review of a substantial change.",
                    },
                )
            },
        )
        if result is None:
            return {}
        answer = result.answers["completion"]
        if (
            answer.choice == "finish"
            or answer.probability < self.policy["completion_probability"]
        ):
            return {}
        message = (
            "Verify the affected behavior or explicitly disclose what remains unverified; do not claim unrun checks passed."
            if answer.choice == "verify"
            else "Consider a bounded read-only architect review of the diff and test evidence; do not repeat an already completed review."
        )
        enforce = (
            self.policy["completion_mode"] == "enforce"
            and not state["discloses_limitation"]
        )
        self.store.log(
            event="completion",
            session=session_key(session),
            status="decision",
            decision_id=result.decision_id,
            decision=answer.choice,
            probability=answer.probability,
            applied=enforce,
        )
        return (
            {"decision": "block", "reason": message}
            if enforce
            else {"systemMessage": "Clef advisory: " + message}
        )
