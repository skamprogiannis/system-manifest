import sys
import re


def rewrite_message():
    try:
        # Read from stdin (git filter-branch passes commit message via stdin)
        original_msg = sys.stdin.read()
    except Exception:
        return

    # Check for "gen(N): message" pattern
    # Use re.DOTALL to capture multi-line messages if the pattern is at the start
    match = re.search(r"^gen\((\d+)\):\s*(.*)", original_msg, re.IGNORECASE | re.DOTALL)

    if not match:
        sys.stdout.write(original_msg)
        return

    gen_num = match.group(1)
    rest_of_msg = match.group(2).strip()

    # Split subject and body
    parts = rest_of_msg.split("\n", 1)
    subject = parts[0].strip()
    body = parts[1].strip() if len(parts) > 1 else ""

    subject_lower = subject.lower()

    # --- Heuristics for Type ---
    msg_type = "chore"  # Default fallback

    if any(
        k in subject_lower
        for k in [
            "fix",
            "repair",
            "bug",
            "crash",
            "error",
            "issue",
            "correct",
            "patch",
            "resolve",
        ]
    ):
        msg_type = "fix"
    elif any(
        k in subject_lower
        for k in ["add", "create", "implement", "enable", "install", "new", "feat"]
    ):
        msg_type = "feat"
    elif any(k in subject_lower for k in ["doc", "readme", "comment", "agents.md"]):
        msg_type = "docs"
    elif any(
        k in subject_lower for k in ["format", "lint", "style", "whitespace", "indent"]
    ):
        msg_type = "style"
    elif any(
        k in subject_lower
        for k in ["refactor", "clean", "structure", "reorganize", "move", "rename"]
    ):
        msg_type = "refactor"
    elif any(k in subject_lower for k in ["optimize", "speed", "performance"]):
        msg_type = "perf"
    elif any(k in subject_lower for k in ["test", "verify"]):
        msg_type = "test"
    elif any(
        k in subject_lower
        for k in ["flake", "lock", "bump", "upgrade", "update inputs"]
    ):
        msg_type = "build"
    elif any(k in subject_lower for k in ["ci", "action", "workflow"]):
        msg_type = "ci"
    elif any(k in subject_lower for k in ["revert"]):
        msg_type = "revert"

    # --- Heuristics for Scope ---
    scopes = []
    if "desktop" in subject_lower or "home-desktop" in subject_lower:
        scopes.append("desktop")
    if "laptop" in subject_lower:
        scopes.append("laptop")
    if "usb" in subject_lower:
        scopes.append("usb")
    if "common" in subject_lower:
        scopes.append("common")
    # 'home' is tricky. If 'home-desktop' matched, we don't want 'home' to match unless it's distinct.
    if "home" in subject_lower and "home-desktop" not in subject_lower:
        scopes.append("home")

    final_scope = ""
    if not scopes:
        # Default scope
        if msg_type in ["build", "ci"]:
            final_scope = "deps"
        else:
            final_scope = "system"
    elif len(scopes) == 1:
        final_scope = scopes[0]
    else:
        # Multiple scopes usually implies common or system-wide change
        final_scope = "common"

    # Construct new message
    # Format: type(scope): subject
    new_subject = f"{msg_type}({final_scope}): {subject}"

    # Preserve the original generation number in the footer
    footer = f"Original-Generation: gen({gen_num})"

    if body:
        new_message = f"{new_subject}\n\n{body}\n\n{footer}"
    else:
        new_message = f"{new_subject}\n\n{footer}"

    sys.stdout.write(new_message)


if __name__ == "__main__":
    rewrite_message()
