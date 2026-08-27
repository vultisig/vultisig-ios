# VultisigDesignSystem

`VultisigDesignSystem` is the shared source of truth for Vultisig colors,
typography, and corner-radius tokens. It depends on `VultisigUIResources` for
the bundled font files and is consumed by both the main app and extensions.

```swift
import VultisigDesignSystem

Text("Vultisig")
    .font(Theme.fonts.bodyMMedium)
    .foregroundStyle(Theme.colors.textPrimary)
```
