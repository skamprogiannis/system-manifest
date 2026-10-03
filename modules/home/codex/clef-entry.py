"""Isolated entrypoint; only the installed module directory is added to sys.path."""

from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
from clef.cli import main

raise SystemExit(main())
