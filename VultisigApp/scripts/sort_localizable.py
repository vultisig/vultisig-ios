#!/usr/bin/env python3
"""Sort Localizable.strings files alphabetically by key, in-place.

Usage:
    python3 sort_localizable.py                  # Sort all 7 locale files
    python3 sort_localizable.py path/to/file.strings  # Sort specific file(s)
"""

import os
import re
import sys

LOCALIZABLES_DIR = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "VultisigApp", "Localizables"
)

LOCALE_DIRS = ["en.lproj", "de.lproj", "es.lproj", "hr.lproj", "it.lproj", "pt.lproj", "zh-Hans.lproj"]

ENTRY_RE = re.compile(r'\s*"([^"]+)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;')


def sort_file(filepath):
    """Sort a single Localizable.strings file in-place."""
    if not os.path.isfile(filepath):
        print(f"  SKIP: {filepath} (not found)")
        return False

    comments = []
    entries = []
    unknown_lines = []

    with open(filepath, "r", encoding="utf-8") as f:
        for line in f:
            stripped = line.strip()
            # Preserve leading comments/empty lines as header
            if not entries and (stripped.startswith("//") or stripped == ""):
                comments.append(line)
                continue
            match = ENTRY_RE.match(line)
            if match:
                entries.append((match.group(1), match.group(2)))
            elif stripped and not stripped.startswith("//"):
                unknown_lines.append(line.rstrip("\n"))

    if unknown_lines:
        print(f"  ERROR: {filepath} contains unsupported lines; aborting to avoid data loss")
        for ul in unknown_lines:
            print(f"    > {ul}")
        return False

    if not entries:
        print(f"  SKIP: {filepath} (no entries found)")
        return False

    entries.sort(key=lambda x: x[0].lower())

    with open(filepath, "w", encoding="utf-8") as f:
        for comment in comments:
            f.write(comment)
        for key, value in entries:
            f.write(f'"{key}" = "{value}";\n')

    print(f"  OK: {filepath} ({len(entries)} entries sorted)")
    return True


def get_all_locale_files():
    """Return paths to all 7 Localizable.strings files."""
    files = []
    for locale in LOCALE_DIRS:
        path = os.path.join(LOCALIZABLES_DIR, locale, "Localizable.strings")
        files.append(path)
    return files


def main():
    if len(sys.argv) > 1:
        files = sys.argv[1:]
    else:
        files = get_all_locale_files()

    print(f"Sorting {len(files)} file(s)...")
    sorted_count = 0
    for f in files:
        if sort_file(f):
            sorted_count += 1

    print(f"Done. {sorted_count}/{len(files)} files sorted.")
    sys.exit(0 if sorted_count == len(files) else 1)


if __name__ == "__main__":
    main()
