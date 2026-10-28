#!/usr/bin/env python3
"""Static check for dynamically-built property tables.

`Kit.new("Class", { ... })`, `Kit.frame(parent, { ... })`, `Build.part({ ... })` and
`Build.disc(..., { ... })` set Instance properties from plain tables, which the Luau type
checker can't verify. This script reads the Roblox API definitions (luau-lsp's
globalTypes.d.luau) and reports any key that isn't a property of the target class.

Usage: python3 tests/check_props.py <path to globalTypes.d.luau>
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Keys our helpers consume themselves (not Instance properties).
HELPER_KEYS = {
    "Kit.frame": {"radius", "Parent"},
    "Build.part": {"Shape", "Parent", "ClassName"},
    "Build.disc": {"Parent"},
    "Kit.new": {"Parent"},
}


def load_classes(defs_path):
    classes = {}
    current = None
    with open(defs_path) as f:
        for line in f:
            m = re.match(r"declare (?:class|extern type) (\w+)(?: extends (\w+))?", line)
            if m:
                current = m.group(1)
                classes[current] = {"parent": m.group(2), "props": set()}
                continue
            if line.startswith("end"):
                current = None
                continue
            if current:
                pm = re.match(r"\s+(?:read\s+)?(\w+)\s*:", line)
                if pm:
                    classes[current]["props"].add(pm.group(1))
    return classes


def has_prop(classes, cls, prop):
    while cls:
        info = classes.get(cls)
        if not info:
            return False
        if prop in info["props"]:
            return True
        cls = info["parent"]
    return False


def table_keys(src, start):
    """Keys at depth 1 of the table literal whose '{' is at src[start]."""
    keys = []
    depth = 0
    i = start
    expect_key = False
    n = len(src)
    while i < n:
        c = src[i]
        if c in "\"'":
            q = c
            i += 1
            while i < n and src[i] != q:
                i += 2 if src[i] == "\\" else 1
        elif c == "-" and src.startswith("--", i):
            while i < n and src[i] != "\n":
                i += 1
        elif c in "({[":
            depth += 1
            if depth == 1 and c == "{":
                expect_key = True
        elif c in ")}]":
            depth -= 1
            if depth == 0:
                return keys
        elif c == "," and depth == 1:
            expect_key = True
        elif depth == 1 and expect_key and not c.isspace():
            m = re.match(r"(\w+)\s*=(?!=)", src[i:])
            if m:
                keys.append(m.group(1))
                i += m.end()
                expect_key = False
                continue
            expect_key = False
        i += 1
    return keys


def find_table_start(src, pos):
    """First '{' at call-argument depth after pos (for helpers whose table is the last argument)."""
    depth = 0
    i = pos
    while i < len(src):
        c = src[i]
        if c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                return None
        elif c == "{" and depth == 1:
            return i
        i += 1
    return None


def main():
    defs = sys.argv[1] if len(sys.argv) > 1 else None
    if not defs or not os.path.exists(defs):
        print("usage: check_props.py <globalTypes.d.luau>")
        sys.exit(2)
    classes = load_classes(defs)
    problems = 0
    checked = 0
    for base, _, files in os.walk(os.path.join(ROOT, "src")):
        for name in files:
            if not name.endswith(".luau"):
                continue
            path = os.path.join(base, name)
            src = open(path).read()
            rel = os.path.relpath(path, ROOT)
            patterns = [
                (r"Kit\.new\(\"(\w+)\"", "Kit.new"),
                (r"Kit\.frame\(", "Kit.frame"),
                (r"Build\.part\(", "Build.part"),
                (r"Build\.disc\(", "Build.disc"),
            ]
            for pattern, helper in patterns:
                for m in re.finditer(pattern, src):
                    if helper == "Kit.new":
                        cls = m.group(1)
                    elif helper == "Kit.frame":
                        cls = "Frame"
                    else:
                        cls = "Part"
                    start = find_table_start(src, m.end() - 1)
                    if start is None:
                        continue
                    keys = table_keys(src, start)
                    if helper == "Build.part" and "ClassName" in keys:
                        cm = re.search(r'ClassName\s*=\s*"(\w+)"', src[start:start + 400])
                        if cm:
                            cls = cm.group(1)
                    for key in keys:
                        checked += 1
                        if key in HELPER_KEYS[helper]:
                            continue
                        if not has_prop(classes, cls, key):
                            line = src.count("\n", 0, start) + 1
                            print(f"{rel}:{line}: '{key}' is not a property of {cls}")
                            problems += 1
    print(f"checked {checked} keys, {problems} problems")
    sys.exit(1 if problems else 0)


if __name__ == "__main__":
    main()
