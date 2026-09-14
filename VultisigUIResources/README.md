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

Remote raster images use `RemoteImageLoader(cache:)`. The containing app and
widget timeline preparation share `RemoteImageCache.shared()` through the App
Group. Only the app may opt into a local fallback if group access is unavailable.
Widget rendering reads prepared files synchronously; it does not start downloads.

HTTPS requests are bounded to 2 MiB and eight seconds, including secure redirect
validation. Supported raster input is normalized to a PNG thumbnail up to 256px
and 512 KiB. Cache files use opaque URL-derived keys, atomic replacement, a
best-effort 64 MiB budget, eight-hour retention protection and seven-day expiry.
Cache misses, invalid images and unavailable storage retain caller fallbacks.
Remote SVG decoding is not provided.

App views keep a bounded decoded-image memory cache to avoid repeated disk reads
while scrolling. Widget timelines downsample prepared images to 120px before
embedding them, preserving the existing 64 KiB inline image limit. CI checks
generated resources before regeneration so missing generated changes fail early.
