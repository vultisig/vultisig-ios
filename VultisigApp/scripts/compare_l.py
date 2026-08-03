#!/usr/bin/env python3
"""Validate every shipping locale against the English localization contract."""

from collections import Counter
from pathlib import Path
import sys

from sort_localizable import ENTRY_RE, LOCALIZABLES_DIR, LOCALE_DIRS

LOCALIZABLES_PATH = Path(LOCALIZABLES_DIR)


def extract_key_counts(filepath):
    """Return every localization key and its occurrence count."""
    with filepath.open(encoding="utf-8") as strings_file:
        return Counter(
            match.group(1)
            for line in strings_file
            if (match := ENTRY_RE.match(line))
        )


def report_duplicates(locale, key_counts):
    """Print duplicate keys and return whether any were found."""
    duplicates = sorted(key for key, count in key_counts.items() if count > 1)
    if not duplicates:
        return False

    print(f"{locale}: {len(duplicates)} duplicate key(s)")
    for key in duplicates:
        print(f"  {key} ({key_counts[key]} occurrences)")
    return True


def main():
    """Require every configured locale to match English exactly once per key."""
    configured_locales = set(LOCALE_DIRS)
    discovered_files = sorted(LOCALIZABLES_PATH.glob("*.lproj/Localizable.strings"))
    discovered_locales = {filepath.parent.name for filepath in discovered_files}

    failed = False
    for locale in sorted(configured_locales - discovered_locales):
        failed = True
        print(f"{locale}: configured locale file is missing")
    for locale in sorted(discovered_locales - configured_locales):
        failed = True
        print(f"{locale}: locale file is not configured in LOCALE_DIRS")

    english_file = LOCALIZABLES_PATH / "en.lproj" / "Localizable.strings"
    if not english_file.is_file():
        print(f"Missing English localization file: {english_file}")
        return 1

    english_counts = extract_key_counts(english_file)
    english_keys = set(english_counts)
    failed = report_duplicates("en", english_counts) or failed

    for locale_dir in LOCALE_DIRS:
        if locale_dir == "en.lproj":
            continue

        filepath = LOCALIZABLES_PATH / locale_dir / "Localizable.strings"
        if not filepath.is_file():
            continue

        locale = filepath.parent.stem
        key_counts = extract_key_counts(filepath)
        locale_keys = set(key_counts)
        duplicate_keys = report_duplicates(locale, key_counts)
        missing_keys = sorted(english_keys - locale_keys)
        unexpected_keys = sorted(locale_keys - english_keys)
        failed = duplicate_keys or failed

        if missing_keys:
            failed = True
            print(f"{locale}: missing {len(missing_keys)} English key(s)")
            for key in missing_keys:
                print(f"  {key}")
        if unexpected_keys:
            failed = True
            print(f"{locale}: contains {len(unexpected_keys)} unexpected key(s)")
            for key in unexpected_keys:
                print(f"  {key}")
        if not duplicate_keys and not missing_keys and not unexpected_keys:
            print(f"{locale}: all {len(english_keys)} English keys present exactly once")

    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
