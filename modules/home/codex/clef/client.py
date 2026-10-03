"""Bounded HTTPS transport and strict System One response validation."""

from dataclasses import dataclass
import http.client
import json
import math
import os
from pathlib import Path
import re
import stat
import time
import tomllib


class ClefError(Exception):
    """An error code safe to show or log without leaking upstream content."""


def private_read(path: Path, limit: int) -> bytes:
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    try:
        info = os.fstat(fd)
        if (
            not stat.S_ISREG(info.st_mode)
            or info.st_uid != os.getuid()
            or info.st_mode & 0o077
        ):
            raise ClefError("insecure_file")
        if info.st_size > limit:
            raise ClefError("input_too_large")
        with os.fdopen(fd, "rb", closefd=False) as handle:
            value = handle.read(limit + 1)
        if len(value) > limit:
            raise ClefError("input_too_large")
        return value
    finally:
        os.close(fd)


def credentials() -> tuple[str, str]:
    # Do not forward these variables to Codex's shell tools. The launcher strips them.
    account = os.environ.get("CLOUDFLARE_ACCOUNT_ID", "")
    token = os.environ.get("CLOUDFLARE_API_TOKEN", "")
    if not account or not token:
        base = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config")
        if not base.is_absolute():
            raise ClefError("invalid_config_home")
        try:
            values = tomllib.loads(
                private_read(base / "cloudflare/clef.toml", 4096).decode()
            )
        except FileNotFoundError:
            raise ClefError("missing_credentials") from None
        except (OSError, ValueError, UnicodeError):
            raise ClefError("invalid_credentials") from None
        account = account or values.get("account_id", "")
        token = token or values.get("api_token", "")
    if not isinstance(account, str) or not re.fullmatch(r"[a-fA-F0-9]{32}", account):
        raise ClefError("invalid_account_id")
    if not isinstance(token, str) or not re.fullmatch(r"[A-Za-z0-9_\-]{20,256}", token):
        raise ClefError("invalid_api_token")
    return account, token


def probability(value: object) -> float:
    if (
        type(value) not in (int, float)
        or not math.isfinite(value)
        or not 0 <= value <= 1
    ):
        raise ClefError("invalid_probability")
    return float(value)


@dataclass(frozen=True)
class Choice:
    choice: str
    probability: float
    confidence: float
    margin: float


@dataclass(frozen=True)
class Result:
    answers: dict[str, Choice]
    input_tokens: int
    output_tokens: int
    latency_ms: int
    decision_id: str = ""


def validate_response(
    body: object, questions: dict, model: str, latency_ms: int = 0
) -> Result:
    if not isinstance(body, dict) or body.get("success") is not True:
        raise ClefError("provider_error")
    result = body.get("result")
    if not isinstance(result, dict) or result.get("model") not in (
        model,
        f"@cf/cloudflare/{model}",
    ):
        raise ClefError("invalid_response_model")
    raw = result.get("answers")
    if not isinstance(raw, dict) or set(raw) != set(questions):
        raise ClefError("invalid_answers")
    answers = {}
    for key, question in questions.items():
        answer = raw[key]
        if not isinstance(answer, dict) or answer.get("type") != "choice":
            raise ClefError("invalid_answer_type")
        probs = answer.get("probabilities")
        if not isinstance(probs, dict) or set(probs) != set(question["criteria"]):
            raise ClefError("invalid_options")
        probs = {option: probability(value) for option, value in probs.items()}
        if not math.isclose(sum(probs.values()), 1.0, abs_tol=0.002):
            raise ClefError("invalid_distribution")
        choice = answer.get("choice")
        if choice not in probs or probs[choice] < max(probs.values()):
            raise ClefError("invalid_choice")
        confidence = probability(answer.get("confidence"))
        ordered = sorted(probs.values(), reverse=True)
        answers[key] = Choice(
            choice, probs[choice], confidence, ordered[0] - ordered[1]
        )
    usage = result.get("usage")
    if not isinstance(usage, dict):
        raise ClefError("invalid_usage")
    for key in ("input_tokens", "output_tokens"):
        if type(usage.get(key)) is not int or not 0 <= usage[key] <= 1_000_000:
            raise ClefError("invalid_usage")
    return Result(answers, usage["input_tokens"], usage["output_tokens"], latency_ms)


def question(instructions: str, criteria: dict[str, str]) -> dict:
    if not 2 <= len(criteria) <= 255:
        raise ClefError("invalid_option_count")
    return {"type": "choice", "instructions": instructions, "criteria": criteria}


class Client:
    def __init__(self, policy: dict):
        self.policy = policy

    def evaluate(
        self, state: object, questions: dict, images: list | None = None
    ) -> Result:
        model = self.policy["provider_model"]
        if model not in ("clef", "clef-flash") or not 1 <= len(questions) <= 64:
            raise ClefError("invalid_request")
        text_payload = {"model": model, "state": state, "questions": questions}
        # Reject instead of silently accepting provider-side context truncation.
        if (
            len(json.dumps(text_payload, ensure_ascii=False).encode())
            > self.policy["max_text_bytes"]
        ):
            raise ClefError("input_too_large")
        if images:
            text_payload["images"] = images
        payload = json.dumps(text_payload, ensure_ascii=False, allow_nan=False).encode()
        if len(payload) > 6_000_000:
            raise ClefError("input_too_large")
        account, token = credentials()
        started = time.monotonic()
        connection = http.client.HTTPSConnection(
            "api.cloudflare.com", timeout=self.policy["timeout_seconds"]
        )
        try:
            connection.request(
                "POST",
                f"/client/v4/accounts/{account}/ai/run/@cf/cloudflare/{model}",
                payload,
                {
                    "Authorization": f"Bearer {token}",
                    "Content-Type": "application/json",
                },
            )
            response = connection.getresponse()
            if response.status != 200:
                raise ClefError(f"http_{response.status}")
            data = response.read(131073)
            if len(data) > 131072:
                raise ClefError("response_too_large")
            body = json.loads(data)
        except (OSError, http.client.HTTPException, ValueError, UnicodeError):
            raise ClefError("transport_error") from None
        finally:
            connection.close()
        elapsed = int((time.monotonic() - started) * 1000)
        return validate_response(body, questions, model, elapsed)
