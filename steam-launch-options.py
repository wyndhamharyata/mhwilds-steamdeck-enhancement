#!/usr/bin/env python3
"""Set Monster Hunter Wilds launch options in Steam's localconfig.vdf."""
import pathlib
import re
import sys

APP = "2246340"
KEY = re.compile(r'^\s*"([^"]+)"(?:\s*("|\{))?')


def brace_delta(line):
    depth = 0
    quoted = False
    escaped = False
    for char in line:
        if quoted:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                quoted = False
        elif char == '"':
            quoted = True
        elif char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
    return depth


def patch(path, value):
    text = path.read_text(errors="surrogateescape")
    lines = text.splitlines(keepends=True)
    escaped = value.replace("\\", "\\\\").replace('"', '\\"')
    depth = 0
    app_depth = None
    pending_app = False
    changed = 0
    for index, line in enumerate(lines):
        stripped = line.strip()
        if pending_app:
            if stripped.startswith("{"):
                app_depth = depth + 1
                pending_app = False
                depth += brace_delta(line)
                continue
            if stripped:
                pending_app = False
        match = KEY.match(line)
        if app_depth is None and match and match.group(1) == APP:
            pending_app = match.group(2) != "{"
            if not pending_app:
                app_depth = depth + 1
        elif app_depth is not None and depth == app_depth and match and match.group(1) == "LaunchOptions":
            indent = line[: len(line) - len(line.lstrip())]
            lines[index] = f'{indent}"LaunchOptions"\t\t"{escaped}"\n'
            changed += 1
        depth += brace_delta(line)
        if app_depth is not None and depth < app_depth:
            app_depth = None
    if not changed:
        return False
    path.write_text("".join(lines), errors="surrogateescape")
    return True


def main():
    if len(sys.argv) != 3:
        raise SystemExit("usage: steam-launch-options.py VDF LAUNCH_OPTIONS")
    path = pathlib.Path(sys.argv[1])
    if patch(path, sys.argv[2]):
        print(f"updated launch options in {path}")
        return 0
    print(f"no Wilds launch options entry found in {path}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
