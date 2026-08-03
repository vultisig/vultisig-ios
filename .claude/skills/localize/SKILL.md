---
name: localize
description: Complete i18n workflow — add keys to every shipping locale, translate, sort. Use when adding or modifying user-facing strings.
---

# Localization Workflow

## Locale Files

The authoritative locale list is `LOCALE_DIRS` in `VultisigApp/scripts/sort_localizable.py`; it currently contains eight locales and includes `ko.lproj`. Update the corresponding `Localizable.strings` file under `VultisigApp/VultisigApp/Core/Localizables/` for every listed locale.

## Usage Pattern in Swift

```swift
// Never hardcode user-facing strings
"myNewKey".localized  // ← uses String extension
```

## Adding a New Key

### Step 1: Choose Key Name
- Use **camelCase**: `vaultSettings`, `sendConfirmTitle`, `errorNetworkFailed`
- Be descriptive and specific

### Step 2: Add to Every Locale
Add the entry to every locale listed in `LOCALE_DIRS`. Translate user-facing prose, but keep established terminology in English when the locale uses it.

**Format:** `"keyName" = "Translation";`

### Translation Examples

Use neighboring entries in each locale's existing `Localizable.strings` file as the terminology reference, including `ko.lproj`.

### Step 3: Sort All Files
```bash
python3 VultisigApp/scripts/sort_localizable.py
```
This sorts every locale listed in `LOCALE_DIRS` in-place alphabetically by key.

## Translation Guidelines

- **Check existing strings** in each locale file for established terminology before translating
- "Chains" means blockchains — each locale has its own established term
- Crypto terms often stay in English (Bitcoin, staking, swap, DeFi)
- When unsure, check what other keys in the same file use for similar concepts
- Keep translations concise — mobile UI has limited space

## Removing Keys

1. Remove the key from every locale listed in `LOCALE_DIRS`
2. Grep the codebase to confirm no remaining `"keyName".localized` references
3. Run sort script after

## Workflow Summary

```text
1. Choose camelCase key name
2. Add "key" = "value"; to every locale listed in LOCALE_DIRS, including ko.lproj
3. Use "key".localized in Swift code
4. Run python3 VultisigApp/scripts/sort_localizable.py
```
