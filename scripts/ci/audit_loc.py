#!/usr/bin/env python3
"""Enforce source and test file size limits."""

from pathlib import Path

AUDIT_ROOTS = (Path("Sources"), Path("Tests"))
AUDITED_EXTENSIONS = {
    ".c",
    ".cc",
    ".cpp",
    ".cxx",
    ".h",
    ".hh",
    ".hpp",
    ".hxx",
    ".iig",
    ".m",
    ".metal",
    ".mm",
    ".swift",
}
MAXIMUM_LINES = 800


def audited_paths() -> list[Path]:
    return [
        path
        for root in AUDIT_ROOTS
        for path in root.rglob("*")
        if path.is_file() and path.suffix in AUDITED_EXTENSIONS
    ]


def line_count(path: Path) -> int:
    return len(path.read_text(encoding="utf-8").splitlines())


def main() -> None:
    paths = audited_paths()
    if not paths:
        raise SystemExit("no source or test files found for the LOC audit")

    counts = [(line_count(path), path) for path in paths]
    oversized = [(count, str(path)) for count, path in counts if count > MAXIMUM_LINES]
    if oversized:
        raise SystemExit(f"files over {MAXIMUM_LINES} LOC: {oversized}")

    print(f"Audited {len(paths)} files; maximum LOC: {max(count for count, _ in counts)}")


if __name__ == "__main__":
    main()
