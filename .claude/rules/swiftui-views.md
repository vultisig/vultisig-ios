---
paths:
  - "VultisigApp/**/*View.swift"
  - "VultisigApp/**/*Screen.swift"
  - "VultisigApp/**/Views/**/*.swift"
  - "VultisigApp/**/Features/**/*.swift"
---

# SwiftUI View Rules

- Use `Theme.colors.*` and `Theme.fonts.*` — never hardcode colors or fonts
- Use price fonts (`priceTitle1`, `priceBodyL`, `priceBodyS`) for numbers and balances
- Use `PrimaryButton` — never create custom button styles
- Use `.foregroundStyle()` — never `.foregroundColor()` (deprecated)
- Use `Screen` component for full-screen views, suffix with `Screen`
- Use `crossPlatformToolbar`, `crossPlatformSheet`, `#if os(macOS)` for cross-platform
- Keep business logic in ViewModels/Services, never in views
- No UIKit unless absolutely necessary
