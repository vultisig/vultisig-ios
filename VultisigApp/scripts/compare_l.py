#!/usr/bin/env python3
"""Fail when a localized strings file is missing an English key."""

import re
import sys
from pathlib import Path


LOCALIZABLES_DIR = (
    Path(__file__).resolve().parents[1]
    / "VultisigApp"
    / "Core"
    / "Localizables"
)
ENTRY_RE = re.compile(r'^\s*"([^"]+)"\s*=')


def extract_keys(filepath):
    """Return all localization keys declared in filepath."""
    with filepath.open(encoding="utf-8") as strings_file:
        return {
            match.group(1)
            for line in strings_file
            if (match := ENTRY_RE.match(line))
        }


def main():
    """Compare every discovered locale against the English key set."""
    english_file = LOCALIZABLES_DIR / "en.lproj" / "Localizable.strings"
    if not english_file.is_file():
        print(f"Missing English localization file: {english_file}")
        return 1

    english_keys = extract_keys(english_file)
    locale_files = sorted(LOCALIZABLES_DIR.glob("*.lproj/Localizable.strings"))
    localized_files = [filepath for filepath in locale_files if filepath != english_file]
    if not localized_files:
        print(f"No localized strings files found in {LOCALIZABLES_DIR}")
        return 1

    failed = False
    for filepath in localized_files:
        locale = filepath.parent.stem
        missing_keys = sorted(english_keys - extract_keys(filepath))
        if missing_keys:
            failed = True
            print(f"{locale}: missing {len(missing_keys)} English key(s)")
            for key in missing_keys:
                print(f"  {key}")
        else:
            print(f"{locale}: all {len(english_keys)} English keys present")

    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
