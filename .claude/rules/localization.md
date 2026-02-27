---
paths:
  - "**/Localizable.strings"
  - "VultisigApp/**/*.swift"
---

# Localization Rules

- Never hardcode user-facing strings — use `"key".localized`
- Add every new key to ALL 7 Localizable.strings files: en, de, es, hr, it, pt, zh-Hans
- Keys must be camelCase and in alphabetical order
- Run `sort_localizable.py` after any changes
- Location: `VultisigApp/Localizables/{lang}.lproj/Localizable.strings`
