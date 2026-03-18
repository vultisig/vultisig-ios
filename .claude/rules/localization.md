---
paths:
  - "**/Localizable.strings"
  - "VultisigApp/**/*.swift"
---

# Localization Rules

- Never hardcode user-facing strings — use `"key".localized`
- Add every new key to ALL 7 Localizable.strings files: en, de, es, hr, it, pt, zh-Hans
- Keys must be camelCase and in alphabetical order
- Run `python3 VultisigApp/scripts/sort_localizable.py` after any changes (sorts all 7 files in-place)
- Use `/localize` skill for the complete i18n workflow with translation examples

## File Paths

| Language | Path |
|----------|------|
| English | `VultisigApp/VultisigApp/Core/Localizables/en.lproj/Localizable.strings` |
| German | `VultisigApp/VultisigApp/Core/Localizables/de.lproj/Localizable.strings` |
| Spanish | `VultisigApp/VultisigApp/Core/Localizables/es.lproj/Localizable.strings` |
| Croatian | `VultisigApp/VultisigApp/Core/Localizables/hr.lproj/Localizable.strings` |
| Italian | `VultisigApp/VultisigApp/Core/Localizables/it.lproj/Localizable.strings` |
| Portuguese | `VultisigApp/VultisigApp/Core/Localizables/pt.lproj/Localizable.strings` |
| Chinese (Simplified) | `VultisigApp/VultisigApp/Core/Localizables/zh-Hans.lproj/Localizable.strings` |

## Common Patterns

- Crypto terms (Bitcoin, swap, DeFi) often stay in English across all locales
- Check existing strings in each locale for established terminology before translating
- "Chains" means blockchains — each locale uses its own established term
