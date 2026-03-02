---
name: ui-components
description: Design system, UI components, Screen, Toolbar, Sheet, and localization reference.
user-invocable: false
---

# UI Components Guide

## Design System

Always use the `Theme` enum for colors and fonts. Never hardcode values.

### Colors (`Theme.colors.*`)

```swift
// Backgrounds
Theme.colors.bgPrimary           // #02122B - Main background (dark navy)
Theme.colors.bgSurface1          // #061B3A - Card/container background
Theme.colors.bgSurface2          // #11284A - Elevated surface
Theme.colors.bgButtonPrimary     // #33E6BF - Primary button (turquoise)
Theme.colors.bgButtonSecondary   // #061B3A - Secondary button
Theme.colors.bgButtonTertiary    // #2155DF - Tertiary button (blue)

// Text
Theme.colors.textPrimary         // #F0F4FC - Primary text (light)
Theme.colors.textSecondary       // #C9D6E8 - Secondary text
Theme.colors.textTertiary        // #8295AE - Tertiary text

// Borders & Alerts
Theme.colors.border              // #1B3F73 - Border color
Theme.colors.alertSuccess        // #13C89D - Success (mint green)
Theme.colors.alertError          // #FF5C5C - Error (red)
Theme.colors.alertWarning        // #FFC25C - Warning (orange)
Theme.colors.turquoise           // #33E6BF - Brand turquoise
```

**Reference:** `VultisigApp/VultisigApp/DesignSystem/DefaultTheme/ColorSystem.swift`

### Fonts (`Theme.fonts.*`)

```swift
// Brockmann family - UI text
Theme.fonts.heroDisplay          // 72pt - Hero text
Theme.fonts.headline             // 40pt - Headlines
Theme.fonts.title1               // 28pt - Large titles
Theme.fonts.title2               // 22pt - Medium titles
Theme.fonts.title3               // 17pt - Small titles
Theme.fonts.bodyLMedium          // 18pt - Large body
Theme.fonts.bodyMMedium          // 16pt - Medium body (most common)
Theme.fonts.bodySMedium          // 14pt - Small body
Theme.fonts.caption12            // 12pt - Captions
Theme.fonts.buttonRegularSemibold // 16pt - Button text

// Satoshi family - ALWAYS use for numbers, prices, and balances
Theme.fonts.priceTitle1          // 28pt
Theme.fonts.priceBodyL           // 18pt
Theme.fonts.priceBodyS           // 14pt
```

**Reference:** `VultisigApp/VultisigApp/DesignSystem/DefaultTheme/FontSystem.swift`

### Gradients

```swift
LinearGradient.primaryGradient           // Turquoise -> Blue (diagonal)
LinearGradient.primaryGradientLinear     // Turquoise -> Blue (vertical)
LinearGradient.primaryGradientHorizontal // Turquoise -> Blue (horizontal)
```

---

## Buttons

Use `PrimaryButton` for **all** buttons. Never create custom button styles.

```swift
PrimaryButton(title: "Continue", type: .primary, size: .medium) {
    // action
}

// With icons
PrimaryButton(title: "Send", leadingIcon: "arrow.up", type: .primary, size: .medium) { }

// Loading state
PrimaryButton(title: "Processing", isLoading: true, type: .primary, size: .medium) { }
```

**Button Types:**
| Type | Appearance |
|------|-----------|
| `.primary` | Blue background (#2155DF) |
| `.secondary` | Dark background with border |
| `.primarySuccess` | Turquoise background (#33E6BF) |
| `.alert` | Red background (#FF5C5C) |
| `.outline` | Transparent with border |

**Button Sizes:** `.medium` (full width, 14pt padding), `.small` (12pt), `.mini` (6pt), `.squared` (12pt radius)

**Reference:** `VultisigApp/VultisigApp/Views/Components/Buttons/PrimaryButton/`

---

## Text Fields

### CommonTextField

General-purpose text input:

```swift
@State private var text = ""
@State private var error: String? = nil
@State private var isValid: Bool? = nil

CommonTextField(
    text: $text,
    label: "Address",
    placeholder: "Enter wallet address",
    error: $error,
    isValid: $isValid
)
```

Sizes: `.normal`, `.small`

**Reference:** `VultisigApp/VultisigApp/Views/Components/TextField/CommonTextField.swift`

### Form Components

| Component | Location | Purpose |
|-----------|----------|---------|
| `AddressTextField` | `Views/Components/Forms/AddressTextField.swift` | Address input with QR/paste accessories |
| `AmountTextField` | `Views/Components/Forms/AmountTextField.swift` | Amount with percentage + ticker |
| `PercentageButtonsStack` | `Views/Components/Forms/PercentageButtonsStack.swift` | 25/50/75/100% quick-select |
| `PercentageSliderView` | `Views/Components/Forms/PercentageSliderView.swift` | Percentage slider input |
| `MemoTextField` | `Views/Components/TextFields/MemoTextField.swift` | Memo/note input |
| `SearchTextField` | `Views/Components/TextField/SearchTextField.swift` | Search input |

---

## Screen Component

Standard wrapper for all full-screen views. **Always use `Screen` for screens and suffix the struct name with `Screen`.**

```swift
struct MyFeatureScreen: View {
    var body: some View {
        Screen(title: "myFeature".localized) {
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 14) {
                    // content
                }
            }
        }
    }
}
```

**Parameters:**
| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `title` | `String` | `""` | Navigation bar title |
| `showNavigationBar` | `Bool` | `true` | Show/hide nav bar |
| `edgeInsets` | `ScreenEdgeInsets` | `.noInsets` | Custom padding |
| `backgroundType` | `BackgroundType` | `.plain` | `.plain` or `.gradient` |

**Default padding:** iOS 16pt horizontal / macOS 40pt horizontal, 12pt vertical

```swift
// Custom insets
Screen(title: "Title", edgeInsets: ScreenEdgeInsets(bottom: 0)) { ... }

// Gradient background (for main screens like Home)
Screen(title: "Title", backgroundType: .gradient) { ... }
```

**Reference:** `VultisigApp/VultisigApp/Views/Components/Screen/Screen.swift`

---

## Cross-Platform Toolbar

Unified toolbar for iOS and macOS.

```swift
content
    .crossPlatformToolbar("Screen Title") {
        CustomToolbarItem(placement: .trailing) {
            ToolbarButton(image: "gear", action: onSettings)
        }
    }
```

**Parameters:** `navigationTitle: String?`, `ignoresTopEdge: Bool = false`, `showsBackButton: Bool = true`, `items: [CustomToolbarItem]`

**ToolbarButton types:** `.outline` (default), `.confirmation` (blue), `.destructive` (red)

```swift
ToolbarButton(image: "checkmark", type: .confirmation, action: onConfirm)
ToolbarButton(image: "trash", type: .destructive, action: onDelete)
ToolbarButton(image: "x", iconSize: 16, action: onClose)
```

**Reference:** `VultisigApp/VultisigApp/Views/Components/Toolbar/CrossPlatformToolbar/`

---

## Cross-Platform Sheet

Unified sheet presentation for iOS and macOS.

```swift
// Boolean
.crossPlatformSheet(isPresented: $showSheet) {
    MySheetContent()
}

// Item-based (item must be Identifiable & Equatable)
.crossPlatformSheet(item: $selectedItem) { item in
    ItemDetailSheet(item: item)
}
```

Sheet content should include:
```swift
.presentationDetents([.medium, .large])
.presentationBackground(Theme.colors.bgSurface1)
.presentationDragIndicator(.visible)
```

**Reference:** `VultisigApp/VultisigApp/Views/Components/Sheet/CrossPlatformSheet.swift`

---

## Containers

```swift
// Modifier approach
VStack { ... }
    .containerStyle(padding: 16, radius: 12, bgColor: Theme.colors.bgSurface1)

// Component approach
ContainerView { ... }
```

**Reference:** `VultisigApp/VultisigApp/Views/Components/Layout/ContainerView.swift`

---

## Icons

```swift
Icon(named: "arrow.up", color: Theme.colors.primaryAccent4, size: 20)
Icon(named: "checkmark", isSystem: true)  // SF Symbol
```

---

## Cell Types

Available in `Views/Components/Cells/`:

| Cell | Purpose |
|------|---------|
| `VaultCell` | Vault display with name, share info |
| `ChainCell` | Chain display |
| `CoinPickerCell` | Coin selection |
| `TransactionCell` | Transaction history row |
| `UTXOTransactionCell` | UTXO-specific transaction |
| `SettingCell` | Settings row |
| `SettingToggleCell` | Settings with toggle |
| `SettingFAQCell` | FAQ setting row |
| `SettingSelectionCell` | Settings with selection |
| `SwapChainCell` / `SwapCoinCell` | Swap selection |
| `PeerCell` / `EmptyPeerCell` | Peer device display |
| `FolderCell` / `FolderVaultCell` | Folder organization |
| `AddressBookCell` | Address book entry |

---

## Banners & Loaders

**Banners:** `Views/Components/Banners/`
- `InfoBannerView` - Info banner with icon, title, message
- `BannerView` - Basic banner
- `ActionBannerView` - Banner with action button
- `OutlinedDisclaimer` - Outlined disclaimer box
- `WarningView` - Warning message

**Loaders:** `Views/Components/Loaders/`
- `Loader` - Main spinner
- `CircularProgressIndicator` - Circular progress with percentage
- `LoadingOverlayViewModifier` - Blocking loading overlay

---

## Segmented Controls

```swift
SegmentedControl(...)      // Standard variant
FilledSegmentedControl(...)  // Filled/solid variant
```

**Reference:** `Views/Components/SegmentedControls/`

---

## View Modifiers

```swift
// Conditional display
.showIf(condition)

// Conditional transformation
.if(condition) { view in view.opacity(0.5) }

// Optional unwrap
.unwrap(optionalValue) { view, value in ... }

// Plain list item (removes background, insets, separator)
.plainListItem()

// Sheet styling (platform-aware)
.sheetStyle(padding: 8)
```

**References:** `Extensions/ViewExtension.swift`, `Views/Components/List/View+PlainListItem.swift`, `Views/Components/Sheet/View+SheetStyling.swift`

---

## Combining Screen + Toolbar + Sheet

```swift
struct MyFeatureScreen: View {
    @State private var showDetailSheet = false
    @State private var selectedItem: Item?

    var body: some View {
        Screen(title: "myFeature".localized) {
            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(items) { item in
                        ItemRow(item: item)
                            .onTapGesture { selectedItem = item }
                    }
                }
            }
        }
        .crossPlatformToolbar {
            CustomToolbarItem(placement: .trailing) {
                ToolbarButton(image: "plus") { showDetailSheet = true }
            }
        }
        .crossPlatformSheet(isPresented: $showDetailSheet) {
            AddItemSheet(isPresented: $showDetailSheet)
        }
        .crossPlatformSheet(item: $selectedItem) { item in
            ItemDetailSheet(item: item)
        }
    }
}
```

---

## Localization

### Supported Languages (7)

| Language | Directory |
|----------|-----------|
| English (base) | `VultisigApp/VultisigApp/Localizables/en.lproj/Localizable.strings` |
| German | `VultisigApp/VultisigApp/Localizables/de.lproj/Localizable.strings` |
| Spanish | `VultisigApp/VultisigApp/Localizables/es.lproj/Localizable.strings` |
| Croatian | `VultisigApp/VultisigApp/Localizables/hr.lproj/Localizable.strings` |
| Italian | `VultisigApp/VultisigApp/Localizables/it.lproj/Localizable.strings` |
| Portuguese | `VultisigApp/VultisigApp/Localizables/pt.lproj/Localizable.strings` |
| Simplified Chinese | `VultisigApp/VultisigApp/Localizables/zh-Hans.lproj/Localizable.strings` |

### Rules

1. **Never hardcode user-facing strings** - Use `"key".localized`
2. **Add to ALL 7 Localizable.strings files** - Every new string must be translated
3. **camelCase keys** - e.g., `"sendCryptoTitle"`, `"vaultSettings"`
4. **Alphabetical ordering** - Keep keys sorted alphabetically within each file
5. **Use `sort_localizable.py`** after adding keys:
   ```bash
   python3 VultisigApp/scripts/sort_localizable.py VultisigApp/VultisigApp/Localizables/en.lproj/Localizable.strings
   ```

### Example

In Swift code:
```swift
Text("sendCryptoTitle".localized)
```

In each `Localizable.strings`:
```
// en.lproj
"sendCryptoTitle" = "Send Crypto";

// de.lproj
"sendCryptoTitle" = "Krypto senden";

// es.lproj
"sendCryptoTitle" = "Enviar Cripto";

// hr.lproj
"sendCryptoTitle" = "Posalji Kripto";

// it.lproj
"sendCryptoTitle" = "Invia Crypto";

// pt.lproj
"sendCryptoTitle" = "Enviar Cripto";

// zh-Hans.lproj
"sendCryptoTitle" = "发送加密货币";
```
