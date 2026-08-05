---
paths:
  - "**/Localizable.strings"
  - "VultisigApp/**/*.swift"
---

# Localization Rules

- Never hardcode user-facing strings — use `"key".localized`
- Add every new key to every locale listed in `VultisigApp/scripts/sort_localizable.py`'s `LOCALE_DIRS`; that list is the source of truth
- Keys must be camelCase and in alphabetical order
- Run `python3 VultisigApp/scripts/sort_localizable.py` after any changes; it sorts every locale in `LOCALE_DIRS` in-place
- Use `/localize` skill for the complete i18n workflow and terminology guidance

## Locale Source of Truth

The authoritative locale set is `LOCALE_DIRS` in `VultisigApp/scripts/sort_localizable.py`. Each entry maps to `VultisigApp/VultisigApp/Core/Localizables/<locale>/Localizable.strings`.

## Common Patterns

- Crypto terms (Bitcoin, swap, DeFi) often stay in English across all locales
- Check existing strings in each locale for established terminology before translating
- "Chains" means blockchains — each locale uses its own established term
