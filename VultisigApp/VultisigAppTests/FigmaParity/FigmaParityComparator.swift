//
//  FigmaParityComparator.swift
//  VultisigAppTests
//
//  A closed-loop visual-diff harness for measuring how closely a SwiftUI view
//  matches its Figma design.
//
//  Pipeline:
//    1. Render the SwiftUI view to a bitmap at an exact point size × scale
//       (ImageRenderer, the same renderer used in-app by ShareSheetViewModel).
//    2. Load the committed Figma export from `FigmaParityReferences/<name>.png`.
//    3. Compute a mask-aware, per-pixel similarity score.
//    4. Write `<name>.actual.png` and `<name>.diff.png` (a red heatmap) to the
//       output directory so the delta can be inspected and localized visually.
//
//  Pixel-exact parity is impossible (status-bar clock, subpixel antialiasing,
//  gradient rasterization). Callers mask volatile regions and gate on a
//  perceptual threshold instead of demanding 1.0.
//

#if canImport(UIKit)
import SwiftUI
import UIKit
import XCTest

@MainActor
enum FigmaParity {

    // MARK: - Result

    struct Result {
        /// Fraction of compared (unmasked) pixels within `tolerance`. 0...1.
        let similarity: Double
        /// Average normalized per-pixel color distance over compared pixels. 0...1.
        let meanDelta: Double
        /// Pixel dimensions the comparison ran at.
        let pixelSize: CGSize
        /// Best global (dx, dy) point-shift and the similarity it would yield —
        /// a non-zero best offset means the layout is uniformly misaligned.
        let bestOffset: (dx: Int, dy: Int)
        let bestOffsetSimilarity: Double
        /// Similarity per horizontal band (top→bottom) to localize the worst regions.
        let bandSimilarities: [Double]
        let actualURL: URL
        let diffURL: URL
        let referenceURL: URL

        var percent: String { String(format: "%.2f%%", similarity * 100) }
    }

    enum ParityError: Error, CustomStringConvertible {
        case renderFailed
        case renderSizeMismatch(actual: CGSize, expected: CGSize)
        case referenceMissing(URL)
        case referenceUnreadable(URL)
        case sizeMismatch(actual: CGSize, reference: CGSize)
        case bitmapFailed
        case pngEncodeFailed(URL)
        case allPixelsMasked

        var description: String {
            switch self {
            case .renderFailed:
                return "ImageRenderer produced no image for the view."
            case .renderSizeMismatch(let actual, let expected):
                return "ImageRenderer produced \(Int(actual.width))×\(Int(actual.height))px but pointSize × scale expects \(Int(expected.width))×\(Int(expected.height))px. Check the pointSize/scale passed to the comparison."
            case .referenceMissing(let url):
                return "Missing Figma reference PNG at \(url.path). Export the frame from Figma and save it there — references are local-only (gitignored); see FigmaParityReferences/README.md."
            case .referenceUnreadable(let url):
                return "Could not decode reference PNG at \(url.path)."
            case .sizeMismatch(let actual, let reference):
                return "Rendered size \(Int(actual.width))×\(Int(actual.height))px != reference \(Int(reference.width))×\(Int(reference.height))px. Re-export the Figma frame at the same point size × scale."
            case .bitmapFailed:
                return "Failed to build an RGBA bitmap context for comparison."
            case .pngEncodeFailed(let url):
                return "Failed to encode PNG data for \(url.path)."
            case .allPixelsMasked:
                return "maskRects cover every pixel — nothing left to compare. Check the mask rects (they are in points, not pixels) against the frame size."
            }
        }
    }

    // MARK: - Public API

    /// Render, diff against the committed reference, write artifacts, return the score.
    ///
    /// - Parameters:
    ///   - view: the SwiftUI view under test.
    ///   - referenceName: file stem under `FigmaParityReferences/` (no extension).
    ///   - pointSize: the Figma frame size in points (e.g. 393×1113).
    ///   - scale: render scale; Figma exports at 3× match device @3x.
    ///   - tolerance: per-pixel normalized distance under which a pixel counts as matching.
    ///   - maskRects: rectangles in POINTS (top-left origin) excluded from comparison
    ///                (e.g. the status bar with its volatile clock / signal icons).
    ///
    /// References and outputs resolve to the harness's own `FigmaParityReferences/`
    /// and `__Output__/` (or the env-var overrides), regardless of where the calling
    /// test file lives — a caller-relative lookup would silently miss the documented
    /// reference directory and skip green.
    @discardableResult
    static func compare(
        _ view: some View,
        against referenceName: String,
        pointSize: CGSize,
        scale: CGFloat = 3,
        tolerance: Double = 0.06,
        maskRects: [CGRect] = []
    ) throws -> Result {
        let actual = try render(view, pointSize: pointSize, scale: scale)

        let width = Int((pointSize.width * scale).rounded())
        let height = Int((pointSize.height * scale).rounded())

        // Validate the render itself before anything else: `pixels(from:)` draws
        // into a fixed-size context, which would silently RESCALE a wrong-sized
        // render and hide renderer/caller scale bugs.
        guard actual.width == width, actual.height == height else {
            throw ParityError.renderSizeMismatch(
                actual: CGSize(width: actual.width, height: actual.height),
                expected: CGSize(width: width, height: height)
            )
        }

        let referenceURL = referencesDirectory().appendingPathComponent("\(referenceName).png")
        guard FileManager.default.fileExists(atPath: referenceURL.path) else {
            // Still emit the actual render so it can be inspected / promoted to reference.
            let actualURL = outputDirectory().appendingPathComponent("\(referenceName).actual.png")
            try writePNG(actual, to: actualURL)
            throw ParityError.referenceMissing(referenceURL)
        }
        guard
            let referenceData = try? Data(contentsOf: referenceURL),
            let referenceImage = UIImage(data: referenceData)?.cgImage
        else {
            throw ParityError.referenceUnreadable(referenceURL)
        }

        guard
            referenceImage.width == width,
            referenceImage.height == height
        else {
            throw ParityError.sizeMismatch(
                actual: CGSize(width: width, height: height),
                reference: CGSize(width: referenceImage.width, height: referenceImage.height)
            )
        }

        let actualPixels = try pixels(from: actual, width: width, height: height)
        let referencePixels = try pixels(from: referenceImage, width: width, height: height)

        let mask = maskBuffer(maskRects, width: width, height: height, scale: scale)

        var matched = 0
        var considered = 0
        var deltaSum = 0.0
        var heatmap = [UInt8](repeating: 0, count: width * height * 4)

        for i in stride(from: 0, to: actualPixels.count, by: 4) {
            let pixelIndex = i / 4
            let masked = mask[pixelIndex]

            let dr = Double(abs(Int(actualPixels[i]) - Int(referencePixels[i]))) / 255.0
            let dg = Double(abs(Int(actualPixels[i + 1]) - Int(referencePixels[i + 1]))) / 255.0
            let db = Double(abs(Int(actualPixels[i + 2]) - Int(referencePixels[i + 2]))) / 255.0
            let delta = (dr + dg + db) / 3.0

            // Dim grayscale of the actual render so heatmap shows *where* the diff is.
            let gray = 0.3 * (Double(actualPixels[i]) + Double(actualPixels[i + 1]) + Double(actualPixels[i + 2])) / 3.0

            if masked {
                // Blue tint marks excluded regions.
                heatmap[i] = UInt8(gray * 0.6)
                heatmap[i + 1] = UInt8(gray * 0.6)
                heatmap[i + 2] = UInt8(min(255.0, gray * 0.6 + 60))
                heatmap[i + 3] = 255
                continue
            }

            considered += 1
            deltaSum += delta
            if delta <= tolerance { matched += 1 }

            let heat = min(1.0, delta * 4.0)
            heatmap[i] = UInt8(min(255.0, gray * (1 - heat) + heat * 255))
            heatmap[i + 1] = UInt8(gray * (1 - heat))
            heatmap[i + 2] = UInt8(gray * (1 - heat))
            heatmap[i + 3] = 255
        }

        // An all-masked comparison would otherwise report a perfect score and
        // silently disable the test (e.g. a mask rect given in pixels, not points).
        guard considered > 0 else {
            throw ParityError.allPixelsMasked
        }

        let similarity = Double(matched) / Double(considered)
        let meanDelta = deltaSum / Double(considered)

        let bands = bandSimilarities(
            actual: actualPixels, reference: referencePixels, mask: mask,
            width: width, height: height, bandCount: 12, tolerance: tolerance
        )
        let (bestOffset, bestOffsetSimilarity) = bestAlignment(
            actual: actualPixels, reference: referencePixels, mask: mask,
            width: width, height: height, tolerance: tolerance, scale: scale, range: 5, stride: 4
        )

        let outDir = outputDirectory()
        let actualURL = outDir.appendingPathComponent("\(referenceName).actual.png")
        let diffURL = outDir.appendingPathComponent("\(referenceName).diff.png")
        try writePNG(actual, to: actualURL)
        if let heatImage = makeImage(from: heatmap, width: width, height: height) {
            try writePNG(heatImage, to: diffURL)
        }

        attach(referenceURL: referenceURL, actualURL: actualURL, diffURL: diffURL, name: referenceName)

        return Result(
            similarity: similarity,
            meanDelta: meanDelta,
            pixelSize: CGSize(width: width, height: height),
            bestOffset: bestOffset,
            bestOffsetSimilarity: bestOffsetSimilarity,
            bandSimilarities: bands,
            actualURL: actualURL,
            diffURL: diffURL,
            referenceURL: referenceURL
        )
    }

    // MARK: - Diagnostics

    /// Similarity within each of `bandCount` horizontal slices (top→bottom).
    private static func bandSimilarities(
        actual: [UInt8], reference: [UInt8], mask: [Bool],
        width: Int, height: Int, bandCount: Int, tolerance: Double
    ) -> [Double] {
        var matched = [Int](repeating: 0, count: bandCount)
        var considered = [Int](repeating: 0, count: bandCount)
        for y in 0..<height {
            let band = min(bandCount - 1, y * bandCount / height)
            let row = y * width
            for x in 0..<width {
                let p = row + x
                if mask[p] { continue }
                let i = p * 4
                let delta = pixelDelta(actual, reference, i, i)
                considered[band] += 1
                if delta <= tolerance { matched[band] += 1 }
            }
        }
        return (0..<bandCount).map { considered[$0] == 0 ? 1.0 : Double(matched[$0]) / Double(considered[$0]) }
    }

    /// Coarse search for a uniform point-shift that maximizes similarity.
    /// `range` is in points; the search steps one point (= `scale` pixels) at a time.
    private static func bestAlignment(
        actual: [UInt8], reference: [UInt8], mask: [Bool],
        width: Int, height: Int, tolerance: Double, scale: CGFloat, range: Int, stride: Int
    ) -> (offset: (dx: Int, dy: Int), similarity: Double) {
        // Similarity with the reference sampled at a uniform (dxPx, dyPx) shift.
        // Masked pixels are skipped at BOTH the actual and the shifted reference
        // coordinate, so volatile regions can't leak into offset candidates.
        func shiftedSimilarity(dxPx: Int, dyPx: Int) -> Double {
            var matched = 0, considered = 0
            var y = 0
            while y < height {
                let ry = y + dyPx
                if ry >= 0 && ry < height {
                    var x = 0
                    while x < width {
                        let rx = x + dxPx
                        let p = y * width + x
                        if rx >= 0 && rx < width && !mask[p] && !mask[ry * width + rx] {
                            let ai = p * 4
                            let ri = (ry * width + rx) * 4
                            considered += 1
                            if pixelDelta(actual, reference, ai, ri) <= tolerance { matched += 1 }
                        }
                        x += stride
                    }
                }
                y += stride
            }
            return considered == 0 ? 0 : Double(matched) / Double(considered)
        }

        let step = max(1, Int(scale.rounded())) // one point, in pixels
        let pxRange = range * step
        // Seed with the unshifted score and only accept strictly better offsets,
        // so ties (flat / mostly-uniform content) report "aligned" instead of
        // the first-scanned corner offset.
        var best = (dx: 0, dy: 0)
        var bestSim = shiftedSimilarity(dxPx: 0, dyPx: 0)
        var dy = -pxRange
        while dy <= pxRange {
            var dx = -pxRange
            while dx <= pxRange {
                let sim = shiftedSimilarity(dxPx: dx, dyPx: dy)
                if sim > bestSim { bestSim = sim; best = (dx / step, dy / step) }
                dx += step
            }
            dy += step
        }
        return (best, bestSim)
    }

    private static func pixelDelta(_ a: [UInt8], _ b: [UInt8], _ ai: Int, _ bi: Int) -> Double {
        let dr = Double(abs(Int(a[ai]) - Int(b[bi]))) / 255.0
        let dg = Double(abs(Int(a[ai + 1]) - Int(b[bi + 1]))) / 255.0
        let db = Double(abs(Int(a[ai + 2]) - Int(b[bi + 2]))) / 255.0
        return (dr + dg + db) / 3.0
    }

    // MARK: - Rendering

    static func render(_ view: some View, pointSize: CGSize, scale: CGFloat) throws -> CGImage {
        let renderer = ImageRenderer(
            content: view
                .frame(width: pointSize.width, height: pointSize.height)
                .environment(\.colorScheme, .dark)
        )
        renderer.scale = scale
        renderer.isOpaque = true
        guard let cgImage = renderer.uiImage?.cgImage else {
            throw ParityError.renderFailed
        }
        return cgImage
    }

    // MARK: - Pixels

    /// Normalize any CGImage into a tightly-packed RGBA8 sRGB buffer.
    private static func pixels(from image: CGImage, width: Int, height: Int) throws -> [UInt8] {
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        // CGContext(data:) does NOT copy or retain the buffer — it draws straight
        // into it, so the pointer must stay valid for the context's ENTIRE use.
        // Passing `&buffer` would hand it a temporary bridged pointer that is only
        // guaranteed valid for the initializer call; pin the array and keep both
        // the context creation and the draw inside the closure instead.
        try buffer.withUnsafeMutableBytes { raw in
            guard
                let base = raw.baseAddress,
                let context = CGContext(
                    data: base,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                )
            else {
                throw ParityError.bitmapFailed
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return buffer
    }

    private static func maskBuffer(_ rects: [CGRect], width: Int, height: Int, scale: CGFloat) -> [Bool] {
        var mask = [Bool](repeating: false, count: width * height)
        guard !rects.isEmpty else { return mask }
        for rect in rects {
            let x0 = max(0, Int((rect.minX * scale).rounded(.down)))
            let y0 = max(0, Int((rect.minY * scale).rounded(.down)))
            let x1 = min(width, Int((rect.maxX * scale).rounded(.up)))
            let y1 = min(height, Int((rect.maxY * scale).rounded(.up)))
            guard x1 > x0, y1 > y0 else { continue }
            for y in y0..<y1 {
                let row = y * width
                for x in x0..<x1 { mask[row + x] = true }
            }
        }
        return mask
    }

    private static func makeImage(from buffer: [UInt8], width: Int, height: Int) -> CGImage? {
        // Same pinning rule as pixels(from:): the context aliases the buffer
        // without copying it, so create the context AND call makeImage() (which
        // snapshots the bits) inside the closure where the pointer is valid.
        var mutable = buffer
        return mutable.withUnsafeMutableBytes { raw -> CGImage? in
            guard
                let base = raw.baseAddress,
                let context = CGContext(
                    data: base,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                )
            else {
                return nil
            }
            return context.makeImage()
        }
    }

    // MARK: - IO

    private static func writePNG(_ image: CGImage, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = UIImage(cgImage: image).pngData() else {
            throw ParityError.pngEncodeFailed(url)
        }
        try data.write(to: url)
    }

    /// Directory of THIS source file — the harness's home. References and
    /// outputs are anchored here (not at the calling test's file), so parity
    /// tests can live anywhere under VultisigAppTests and still resolve the
    /// single documented `FigmaParityReferences/` + `__Output__/` location.
    private static let harnessDirectory = URL(fileURLWithPath: "\(#filePath)").deletingLastPathComponent()

    /// Internal (not private) so record-mode tests can write a new reference to
    /// exactly the location `compare` will read it from.
    static func referencesDirectory() -> URL {
        // References are local-only (gitignored). Override the location with
        // FIGMA_PARITY_REFS to keep them entirely outside the repo tree.
        if let override = ProcessInfo.processInfo.environment["FIGMA_PARITY_REFS"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return harnessDirectory.appendingPathComponent("FigmaParityReferences", isDirectory: true)
    }

    private static func outputDirectory() -> URL {
        if let override = ProcessInfo.processInfo.environment["FIGMA_PARITY_OUT"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return harnessDirectory.appendingPathComponent("__Output__", isDirectory: true)
    }

    private static func attach(referenceURL: URL, actualURL: URL, diffURL: URL, name: String) {
        XCTContext.runActivity(named: "Figma parity: \(name)") { activity in
            for (label, url) in [("figma", referenceURL), ("actual", actualURL), ("diff", diffURL)] {
                guard let image = UIImage(contentsOfFile: url.path) else { continue }
                let attachment = XCTAttachment(image: image)
                attachment.name = "\(name).\(label)"
                attachment.lifetime = .keepAlways
                activity.add(attachment)
            }
        }
    }
}

// MARK: - Assertion helper

/// Gates on **perceptual precision** (`1 − meanDelta`) rather than strict per-pixel
/// coverage: dense text can never be pixel-identical between Figma's renderer and
/// iOS CoreText, so strict coverage floors in the mid-90s even when a screen is
/// visually perfect. `similarity` (coverage) is still reported for context.
///
/// References are **local-only** (gitignored). When one isn't present the check is
/// SKIPPED (not failed), so a fresh checkout / CI stays green — this is throwing so
/// the `XCTSkip` propagates; call it with `try` from a `throws` test.
@MainActor
func assertFigmaParity(
    _ view: some View,
    reference: String,
    pointSize: CGSize,
    scale: CGFloat = 3,
    perceptualThreshold: Double = 0.95,
    tolerance: Double = 0.06,
    maskRects: [CGRect] = [],
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    let result: FigmaParity.Result
    do {
        result = try FigmaParity.compare(
            view,
            against: reference,
            pointSize: pointSize,
            scale: scale,
            tolerance: tolerance,
            maskRects: maskRects
        )
    } catch let FigmaParity.ParityError.referenceMissing(url) {
        throw XCTSkip("Figma reference not found (local-only): \(url.path). Export the frame from Figma to enable this check; the current render was written to __Output__ for inspection.")
    } catch {
        XCTFail("Figma parity '\(reference)' errored: \(error)", file: file, line: line)
        return
    }

    let perceptual = 1 - result.meanDelta
    let bands = result.bandSimilarities
        .enumerated()
        .map { "b\($0.offset)=\(String(format: "%.0f", $0.element * 100))" }
        .joined(separator: " ")
    let offset = result.bestOffset
    let offsetNote = (offset.dx == 0 && offset.dy == 0)
        ? "aligned"
        : "shift(dx:\(offset.dx),dy:\(offset.dy))→\(String(format: "%.1f%%", result.bestOffsetSimilarity * 100))"
    let message = """
    Figma parity '\(reference)': perceptual \(String(format: "%.2f%%", perceptual * 100)) (gate \(String(format: "%.2f%%", perceptualThreshold * 100))), coverage \(result.percent) @tol \(tolerance) (meanDelta \(String(format: "%.4f", result.meanDelta))).
      bestAlign: \(offsetNote)
      bands(top→bottom %): \(bands)
      actual: \(result.actualURL.path)
      diff:   \(result.diffURL.path)
      figma:  \(result.referenceURL.path)
    """
    XCTAssertGreaterThanOrEqual(perceptual, perceptualThreshold, message, file: file, line: line)
    // Always surface the numbers, pass or fail, so the loop can watch convergence.
    print("▶︎ " + message)
}
#endif
