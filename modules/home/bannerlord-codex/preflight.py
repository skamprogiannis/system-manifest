"""Read-only CLI/auth checks. Never emit account status output or credentials."""
import subprocess
import sys

from codex_runner import environment

EXPECTED_VERSION = "codex-cli 0.154.0"


class PreflightError(Exception):
    pass


def check(executable="codex"):
    for args, expected, message in (
        (["--version"], EXPECTED_VERSION, "Codex CLI 0.154.0 is required for this adapter."),
        (["login", "status"], "Logged in using ChatGPT",
         "Sign into Codex with your ChatGPT account first; API-key authentication is not accepted."),
    ):
        try:
            result = subprocess.run([executable, *args], env=environment(),
                                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                    text=True, encoding="utf-8", timeout=10)
        except (OSError, subprocess.TimeoutExpired):
            raise PreflightError("The local Codex preflight could not complete.") from None
        if result.returncode or expected not in (line.strip() for line in result.stdout.splitlines()):
            raise PreflightError(message)


if __name__ == "__main__":
    try:
        check()
    except PreflightError as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(1)
    print("Codex version and saved ChatGPT sign-in checked locally; quota remains unverified.")
