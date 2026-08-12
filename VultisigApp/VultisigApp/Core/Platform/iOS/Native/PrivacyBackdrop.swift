//
//  PrivacyBackdrop.swift
//  VultisigApp
//

#if os(iOS)
import CoreImage
import SwiftUI
import UIKit

/// A picture of the app blurred past reading — what the privacy cover shows over
/// the app while it is away.
///
/// It exists for the *return*, not the departure. What the user sees coming back
/// is the app-switcher card, drawn as they left and zoomed to full screen by the
/// system: a picture, settled before the app has any say in it. A card carrying a
/// different screen than the one behind it cannot be dissolved on the way in,
/// however early the app uncovers — it reads as a cut. A blurred copy of the
/// screen keeps the layout, so the same animation reads as the app coming into
/// focus.
///
/// A captured bitmap rather than a `UIVisualEffectView`, and that is not a
/// preference. A visual-effect view samples the backdrop *of its own window*, and
/// the cover is carried in a window raised above the app's precisely so that it
/// covers sheets and alerts too. There is nothing behind it there to sample: it
/// paints its material over an empty backdrop and comes out a flat slab, with the
/// layout — the whole reason for blurring the screen rather than replacing it —
/// gone. That was measured, not assumed.
enum PrivacyBackdrop {

    /// How much of the screen's resolution survives the capture.
    ///
    /// Low enough that a balance is a smudge before a blur is applied at all,
    /// which is also what makes this cheap enough to run on the way out: the
    /// render is a small fraction of the screen's pixels. The two steps are
    /// belt and braces rather than a division of labour — neither is trusted
    /// alone, and if either fails there is no picture at all.
    private static let captureScale: CGFloat = 0.12
    /// Applied to the *downscaled* picture, so it goes a long way: at an eighth
    /// of the resolution this is worth eight times as much as it would be at
    /// full size. Enough to take the stair-stepping off the upscale, and no more
    /// — past that the cards and rows dissolve into a wash, and a wash is the
    /// scene change the blur exists to avoid.
    private static let blurSigma: Double = 1.6

    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    /// The picture the cover is currently showing, or `nil` when there is none
    /// and ``CoverView`` should fall back to the brand screen.
    ///
    /// Shared state rather than each host taking its own, because the app draws
    /// the cover in two places — its own overlay and the raised window — and the
    /// two must not be able to draw *different things*. They could: the overlay
    /// renders in the same pass that raises the cover, while the window is put up
    /// afterwards and, the first time, has a whole `UIWindow` to build and lay
    /// out first. With a picture each, the overlay's brand-screen fallback landed
    /// first and the window's blur replaced it a frame or two later — a logo
    /// flashing over the wallet on the way out, which is precisely what the blur
    /// exists to stop.
    private(set) static var latest: Image?

    /// Takes the picture, **before** the cover goes up.
    ///
    /// The ordering is the whole point and it is not an optimisation: the first
    /// frame in which anything is covered must already have this to draw, or the
    /// fallback shows for that frame and the flash is back. Called from the
    /// scene-phase hook, one step ahead of the flag.
    ///
    /// Answers `nil` on any failure, which is the safe direction: no picture
    /// means the brand screen, in both hosts at once.
    static func take() {
        latest = UIApplication.shared.activeContentWindow
            .flatMap(picture(of:))
            .map(Image.init(uiImage:))
    }

    /// Dropped as soon as the app is uncovered — this is a photograph of a
    /// wallet, and nothing needs it once there is nothing to cover.
    static func discard() {
        latest = nil
    }

    static func picture(of window: UIWindow) -> UIImage? {
        let bounds = window.bounds
        guard bounds.width > 0, bounds.height > 0 else { return nil }

        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale = captureScale
        format.opaque = true

        let small = UIGraphicsImageRenderer(bounds: bounds, format: format).image { _ in
            // `afterScreenUpdates: false`, and it is load bearing. The cover this
            // picture is *for* has just been raised, so the app's own overlay copy
            // of it is already pending in this very hierarchy; waiting for the
            // screen to update would capture that logo instead of the wallet the
            // card is supposed to show. Drawing what is currently on screen takes
            // the frame from before the cover, which is the one wanted — and costs
            // no render pass on the way out.
            window.drawHierarchy(in: bounds, afterScreenUpdates: false)
        }

        // Nothing partial is ever returned. A failure here answers `nil` and
        // ``CoverView`` shows the brand screen instead, which conceals more than
        // this ever does.
        //
        // The downscaled picture on its own is *not* the fallback, tempting as it
        // is to treat "too small to read" as good enough. It is not a
        // confidentiality boundary: a balance set in a display face, and a
        // receive-address QR at iPad size, both survive an eighth-scale
        // reduction better than intuition suggests, and this picture is what
        // becomes the app-switcher card — the one artefact here that outlives
        // the moment.
        guard let source = CIImage(image: small) else { return nil }
        // Clamped first, or the blur samples transparent black from beyond the
        // edges and leaves a dark vignette all the way round.
        let blurred = source
            .clampedToExtent()
            .applyingGaussianBlur(sigma: blurSigma)
            .cropped(to: source.extent)

        guard let rendered = context.createCGImage(blurred, from: blurred.extent) else { return nil }
        return UIImage(cgImage: rendered)
    }
}
#endif
