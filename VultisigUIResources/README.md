# VultisigUIResources

`VultisigUIResources` owns fonts and images that must render identically in
the Vultisig app and its extensions. Keeping them in a Swift package gives
each target a bundle-safe way to load the same source assets without copying
files between targets.

Use `VultisigFont` for custom fonts and `VultisigImage` for package images:

```swift
import VultisigUIResources

Text("Vultisig")
    .font(VultisigFont.brockmannMedium.font(size: 16))

VultisigImage.logoOutline.image
```

Call `VultisigResources.registerFonts()` during application or extension
startup when code outside SwiftUI creates fonts directly by PostScript name.
