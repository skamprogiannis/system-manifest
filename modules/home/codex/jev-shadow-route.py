#!/usr/bin/env python3
"""Append sanitized Jev shadow-routing metadata without retaining prompts."""

import argparse
import json
import os
from datetime import datetime, timezone
from pathlib import Path


def bounded_float(value: str) -> float:
    parsed = float(value)
    if not 0.0 <= parsed <= 1.0:
        raise argparse.ArgumentTypeError("must be between 0 and 1")
    return parsed


def nonnegative_int(value: str) -> int:
    parsed = int(value)
    if parsed < 0:
        raise argparse.ArgumentTypeError("must be non-negative")
    return parsed


def nonnegative_float(value: str) -> float:
    parsed = float(value)
    if parsed < 0.0:
        raise argparse.ArgumentTypeError("must be non-negative")
    return parsed


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Record sanitized Jev shadow-routing metadata; never accepts prompt text."
    )
    parser.add_argument("--task-kind", required=True, choices=("coding", "research", "review", "planning", "other"))
    parser.add_argument("--proposed-tier", required=True, choices=("none", "fast", "standard", "reasoning"))
    parser.add_argument("--effort", required=True, choices=("low", "medium", "high", "xhigh"))
    parser.add_argument("--probability", required=True, type=bounded_float)
    parser.add_argument("--latency-ms", type=nonnegative_int)
    parser.add_argument("--usage-tokens", type=nonnegative_int)
    parser.add_argument("--estimated-cost-usd", type=nonnegative_float)
    args = parser.parse_args()

    entry = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "task_kind": args.task_kind,
        "proposed_tier": args.proposed_tier,
        "effort": args.effort,
        "probability": args.probability,
    }
    if args.latency_ms is not None:
        entry["latency_ms"] = args.latency_ms
    if args.usage_tokens is not None:
        entry["usage_tokens"] = args.usage_tokens
    if args.estimated_cost_usd is not None:
        entry["estimated_cost_usd"] = args.estimated_cost_usd

    state_dir = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")) / "codex-jev"
    state_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
    log_file = state_dir / "shadow.jsonl"
    with log_file.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(entry, separators=(",", ":")) + "\n")
    os.chmod(log_file, 0o600)


if __name__ == "__main__":
    main()
