#!/usr/bin/env python3
"""Reject `///` doc comments outside the public API.

Usage: audit_docs.py [--fix] SYMBOL_GRAPH_DIR

The public symbol graph names the doc comment lines of every declaration a client sees,
including implicitly public enum cases and protocol requirements. Any other `///` line in
Sources or Tests documents code no client sees. `--fix` deletes those lines.
"""

import json
import sys
from pathlib import Path
from urllib.parse import unquote, urlparse

AUDIT_ROOTS = (Path("Sources"), Path("Tests"))
EXTRA_FILES = (Path("Package.swift"),)


def public_doc_lines(graph_dir: Path) -> dict[Path, set[int]]:
    lines: dict[Path, set[int]] = {}
    for graph in graph_dir.glob("*.symbols.json"):
        for symbol in json.loads(graph.read_text())["symbols"]:
            comment = symbol.get("docComment")
            if not comment or "uri" not in comment:
                continue
            path = Path(unquote(urlparse(comment["uri"]).path)).resolve()
            covered = lines.setdefault(path, set())
            for line in comment["lines"]:
                if "range" in line:
                    covered.add(line["range"]["start"]["line"])
    return lines


def comment_lines(text: list[str]) -> list[int]:
    """Indexes of `///` lines outside multi-line string literals, such as test fixtures."""
    indexes, in_string = [], False
    for index, line in enumerate(text):
        if not in_string and line.lstrip().startswith("///"):
            indexes.append(index)
        if line.count('"""') % 2:
            in_string = not in_string
    return indexes


def audited_paths() -> list[Path]:
    paths = [path for root in AUDIT_ROOTS for path in root.rglob("*.swift")]
    return sorted(paths + [path for path in EXTRA_FILES if path.exists()])


def main() -> int:
    arguments = sys.argv[1:]
    fix = "--fix" in arguments
    arguments = [argument for argument in arguments if argument != "--fix"]
    if len(arguments) != 1:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    public = public_doc_lines(Path(arguments[0]))
    violations = 0
    for path in audited_paths():
        covered = public.get(path.resolve(), set())
        text = path.read_text().splitlines(keepends=True)
        stray = [index for index in comment_lines(text) if index not in covered]
        if not stray:
            continue
        violations += len(stray)
        if fix:
            path.write_text("".join(l for i, l in enumerate(text) if i not in set(stray)))
        else:
            for index in stray:
                print(f"{path}:{index + 1}: doc comment on a non-public declaration")
    if violations and not fix:
        print(f"ERROR: {violations} doc comment lines outside the public API")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
