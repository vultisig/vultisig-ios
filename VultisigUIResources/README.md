# VultisigUIResources

This package owns the canonical image catalog and fonts used by the app and its
extensions. Source artwork lives only in `Resources/Images.xcassets`; application
icons and accent configuration remain in the app catalog.

Use `VultisigResources.image(named:)` for optional runtime names, or
`Image(name, bundle: VultisigResources.bundle)` when the asset is known. Native
image callers use `VultisigResources.platformImage(named:)`. `VultisigImage`
retains convenient names for commonly used brand/token artwork; it does not
restrict which images are available.

`make generate` derives the bundled name index and shared typed `ImageResource`
properties from the catalog using Xcode's symbol names. App and widget compile
the same generated forwarding file, which points every typed resource to the
package bundle. Do not edit generated names or maintain separate allowlists.
`python3 scripts/generate-image-resources.py --check` checks catalog consistency.
`make lint-icons` checks literal asset references and duplicate names.

Register custom fonts with `VultisigResources.registerFonts()` when creating
fonts directly by PostScript name outside SwiftUI.
