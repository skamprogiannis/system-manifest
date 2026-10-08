"""Apply bounded account-bootstrap recovery to local terminal sessions only."""

import os
from pathlib import Path
import sys



def normalize_terminfo_search():
    """Discard absent optional Nix profiles, retaining custom path diagnostics."""
    raw = os.environ.get("TERMINFO_DIRS")
    if raw is None:
        return
    home = Path(os.environ.get("HOME") or Path.home())
    optional = {
        str(home / ".nix-profile/share/terminfo"),
        str(home / ".local/state/nix/profile/share/terminfo"),
        "/nix/profile/share/terminfo",
        "/nix/var/nix/profiles/default/share/terminfo",
    }
    entries = raw.split(os.pathsep)
    # Empty entries mean ncurses' default search path and must survive.
    os.environ["TERMINFO_DIRS"] = os.pathsep.join(
        entry for entry in entries
        if entry not in optional or Path(entry).exists()
    )


def main():
    normalize_terminfo_search()
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
