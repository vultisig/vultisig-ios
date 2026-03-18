---
name: localize
description: Complete i18n workflow — add keys to all 7 locale files, translate, sort. Use when adding or modifying user-facing strings.
disable-model-invocation: true
---

# Localization Workflow

## Locale Files (ALL 7 must be updated)

| Language | Path |
|----------|------|
| English | `VultisigApp/VultisigApp/Core/Localizables/en.lproj/Localizable.strings` |
| German | `VultisigApp/VultisigApp/Core/Localizables/de.lproj/Localizable.strings` |
| Spanish | `VultisigApp/VultisigApp/Core/Localizables/es.lproj/Localizable.strings` |
| Croatian | `VultisigApp/VultisigApp/Core/Localizables/hr.lproj/Localizable.strings` |
| Italian | `VultisigApp/VultisigApp/Core/Localizables/it.lproj/Localizable.strings` |
| Portuguese | `VultisigApp/VultisigApp/Core/Localizables/pt.lproj/Localizable.strings` |
| Chinese (Simplified) | `VultisigApp/VultisigApp/Core/Localizables/zh-Hans.lproj/Localizable.strings` |

## Usage Pattern in Swift

```swift
// Never hardcode user-facing strings
"myNewKey".localized  // ← uses String extension
```

## Adding a New Key

### Step 1: Choose Key Name
- Use **camelCase**: `vaultSettings`, `sendConfirmTitle`, `errorNetworkFailed`
- Be descriptive and specific

### Step 2: Add to ALL 7 Files
Add the entry to each file. Use proper translations — do not leave English in non-English files.

**Format:** `"keyName" = "Translation";`

### Translation Examples

| Key | en | de | es | hr | it | pt | zh-Hans |
|-----|----|----|----|----|----|----|---------|
| send | Send | Senden | Enviar | Pošalji | Invia | Enviar | 发送 |
| cancel | Cancel | Abbrechen | Cancelar | Otkaži | Annulla | Cancelar | 取消 |
| settings | Settings | Einstellungen | Configuración | Postavke | Impostazioni | Configurações | 设置 |
| vault | Vault | Tresor | Bóveda | Trezor | Cassaforte | Cofre | 金库 |
| done | Done | Fertig | Hecho | Gotovo | Fatto | Concluído | 完成 |
| error | Error | Fehler | Error | Greška | Errore | Erro | 错误 |
| loading | Loading... | Laden... | Cargando... | Učitavanje... | Caricamento... | Carregando... | 加载中... |
| save | Save | Speichern | Guardar | Spremi | Salva | Salvar | 保存 |
| delete | Delete | Löschen | Eliminar | Obriši | Elimina | Excluir | 删除 |

### Step 3: Sort All Files
```bash
python3 VultisigApp/scripts/sort_localizable.py
```
This sorts all 7 files in-place alphabetically by key.

## Translation Guidelines

- **Check existing strings** in each locale file for established terminology before translating
- "Chains" means blockchains — each locale has its own established term
- Crypto terms often stay in English (Bitcoin, staking, swap, DeFi)
- When unsure, check what other keys in the same file use for similar concepts
- Keep translations concise — mobile UI has limited space

## Removing Keys

1. Remove the key from **all 7** locale files
2. Grep the codebase to confirm no remaining `"keyName".localized` references
3. Run sort script after

## Workflow Summary

```text
1. Choose camelCase key name
2. Add "key" = "value"; to all 7 files
3. Use "key".localized in Swift code
4. Run python3 VultisigApp/scripts/sort_localizable.py
```
