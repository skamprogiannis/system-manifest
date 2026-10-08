"""Apply bounded account-bootstrap recovery to local terminal sessions only."""

import os
import sys


def main():
    binary, source, *arguments = sys.argv[1:]
    if (
        all(stream.isatty() for stream in (sys.stdin, sys.stdout, sys.stderr))
        and os.environ.get("CODEX_CLEF_ENABLED") != "1"
    ):
        sys.path.insert(0, source)
        from clef.cli import launch_context
        from clef.startup import launch_interactive

        if launch_context(arguments).interactive:
            return launch_interactive(binary, [binary, *arguments], dict(os.environ))
    os.execv(binary, [binary, *arguments])


if __name__ == "__main__":
    raise SystemExit(main())
