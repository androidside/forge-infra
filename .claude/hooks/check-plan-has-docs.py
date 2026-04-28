#!/usr/bin/env python3
"""
PreToolUse hook for the ExitPlanMode tool.

Informational nudge (non-blocking). Reads the tool call payload from stdin
(JSON; the plan markdown is in tool_input.plan), and if the plan does not
appear to update docs/*.md, prints a hint to stderr listing the categories
of change that warrant a docs update. Always exits 0 so plan mode proceeds.

The intent is to remind, not to block. If the plan is a refactor, a bug fix,
or any change without a user-facing surface, ignoring the hint is correct.
"""

import json
import re
import sys


DOC_HINTS = [
    r"docs/[A-Z][A-Z0-9_-]+\.md",            # explicit docs/FILENAME.md mention
    r"\bUpdate docs\b",                       # task title
    r"\bdocumentation\s+(update|refresh)\b",  # generic phrasing
]


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except json.JSONDecodeError:
        return 0

    plan = (payload.get("tool_input") or {}).get("plan") or ""
    if not plan:
        return 0

    for pattern in DOC_HINTS:
        if re.search(pattern, plan, re.IGNORECASE):
            return 0

    sys.stderr.write(
        "Plan-mode docs check (informational, non-blocking): this plan does not "
        "appear to update docs/*.md. If the plan introduces any of:\n"
        "  - new env variables\n"
        "  - new pipeline observability messages or event types\n"
        "  - new pipeline steps\n"
        "  - new database tables or schema changes\n"
        "  - new ways of managing teams or other cross-cutting feature surfaces\n"
        "  - new API endpoints exposed to the frontend\n"
        "consider adding an 'Update docs' task that lists the affected docs/*.md "
        "files. For internal refactors, bug fixes, or changes without a user-facing "
        "surface, ignore this hint.\n"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
