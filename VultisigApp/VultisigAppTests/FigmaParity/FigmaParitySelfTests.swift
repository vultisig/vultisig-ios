//
//  FigmaParitySelfTests.swift
//  VultisigAppTests
//
//  Hermetic self-validation of the FigmaParity comparator. Real parity checks
//  diff against local-only Figma exports and therefore SKIP on fresh checkouts;
//  these tests instead diff a test-target-only SwiftUI fixture against a
//  COMMITTED reference PNG (the one un-gitignored file in FigmaParityReferences/),
//  so the comparator's mechanics run on every CI pass:
//    1. identical content passes a tight perceptual gate,
//    2. deliberately altered content scores measurably lower,
//    3. translated content is caught, with bestAlign reporting the offset.
//
//  Determinism: the fixture is deliberately TEXT-FREE (solid fills, one linear
//  and one radial gradient, plain shapes) because text antialiasing is the one
//  part of the pipeline that varies across machines/OS versions (Figma vs
//  CoreText is the documented parity floor; CoreText vs CoreText across OS
//  releases can drift too). Shape/gradient rasterization through ImageRenderer
//  is CPU-side CoreGraphics and stable; residual sub-pixel edge differences are
//  absorbed by the default 6% per-pixel tolerance and the head-roomed gates and
//  relative (baseline-vs-variant) assertions below.
//
//  Regenerating the committed reference (also documented in
//  FigmaParityReferences/README.md): run the record-mode test with the env var
//  set, inspect the written PNG visually, and commit it:
//
//    TEST_RUNNER_FIGMA_PARITY_RECORD=1 xcodebuild test \
//      -project VultisigApp.xcodeproj -scheme VultisigApp \
//      -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
//      -only-testing:VultisigAppTests/FigmaParitySelfTests/testRecordSelfTestReference
//

// The comparator is UIKit-backed (UIImage encode/decode, XCTAttachment), so the
// suite is compiled out where UIKit is unavailable. In practice this target
// only builds for iOS anyway (project.yml `supportedDestinations: [iOS]`; the
// macOS CI job builds the app scheme without test targets), so the guard is
// belt-and-braces rather than an active platform split.
#if canImport(UIKit)
import SwiftUI
import UIKit
import XCTest

// MARK: - Fixture

/// Test-only, text-free view the self-tests render and diff. Needs no Figma
/// export and no app screen; geometry and colors are fixed constants so the
/// render is reproducible anywhere the target runs.
private struct ParityFixtureView: View {
    static let pointSize = CGSize(width: 120, height: 120)

    /// Color of the disc in the lower-right quadrant; the "altered" variant changes it.
    var discColor = Color(red: 0.95, green: 0.55, blue: 0.15)
    /// Uniform content shift in points; the "translated" variant sets it.
    var contentOffset = CGSize.zero

    var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.08, blue: 0.16)
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.20, green: 0.45, blue: 0.95),
                                Color(red: 0.10, green: 0.85, blue: 0.75)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: 84, height: 36)
                    .position(x: 52, y: 32)
                Circle()
                    .fill(discColor)
                    .frame(width: 40, height: 40)
                    .position(x: 86, y: 84)
                Rectangle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 0.55, green: 0.35, blue: 0.95),
                                Color(red: 0.08, green: 0.12, blue: 0.30)
                            ],
                            center: .center,
                            startRadius: 2,
                            endRadius: 26
                        )
                    )
                    .frame(width: 34, height: 34)
                    .position(x: 30, y: 88)
            }
            .offset(contentOffset)
        }
    }
}

// MARK: - Tests

@MainActor
final class FigmaParitySelfTests: XCTestCase {

    private let referenceName = "selftest-fixture"

    /// The unmodified fixture must clear a gate far tighter than the real-world
    /// 0.95 floor — identical content through the same renderer should be
    /// near-exact, with 0.99 leaving headroom for cross-OS rasterization drift.
    /// Exercises the public `assertFigmaParity` entry point end to end.
    func testFixtureMatchesCommittedReference() throws {
        try assertFigmaParity(
            ParityFixtureView(),
            reference: referenceName,
            pointSize: ParityFixtureView.pointSize,
            perceptualThreshold: 0.99
        )
    }

    /// A color change on ~9% of the pixels (the disc) must be measurably worse
    /// than the unmodified render on both metrics, and must land below the
    /// tight gate the identity test passes. Assertions are relative to a
    /// same-run baseline so cross-machine render drift cancels out.
    func testAlteredFixtureScoresMeasurablyLower() throws {
        let baseline = try compareOrSkip(ParityFixtureView())
        let altered = try compareOrSkip(
            ParityFixtureView(discColor: Color(red: 0.10, green: 0.90, blue: 0.30))
        )

        XCTAssertEqual(baseline.bestOffset.dx, 0, "unmodified fixture should be aligned")
        XCTAssertEqual(baseline.bestOffset.dy, 0, "unmodified fixture should be aligned")
        XCTAssertGreaterThan(
            altered.meanDelta, baseline.meanDelta + 0.01,
            "recoloring the disc must raise meanDelta well past the baseline"
        )
        XCTAssertLessThan(
            altered.similarity, baseline.similarity - 0.02,
            "recoloring the disc must drop strict per-pixel coverage"
        )
        XCTAssertLessThan(
            1 - altered.meanDelta, 0.99,
            "the altered render must fail the perceptual gate the identity test passes"
        )
    }

    /// Shifting the content by a whole-point offset must be caught, and
    /// `bestAlign` must name the exact shift: content moved right/down by
    /// (3, 2)pt matches the reference again when read back at (-3, -2).
    func testTranslatedFixtureReportsAlignmentOffset() throws {
        let translated = try compareOrSkip(
            ParityFixtureView(contentOffset: CGSize(width: 3, height: 2))
        )

        XCTAssertEqual(translated.bestOffset.dx, -3, "bestAlign should recover the horizontal shift")
        XCTAssertEqual(translated.bestOffset.dy, -2, "bestAlign should recover the vertical shift")
        XCTAssertGreaterThan(
            translated.bestOffsetSimilarity, translated.similarity,
            "similarity at the recovered offset must beat the unshifted comparison"
        )
    }

    /// Masking every pixel must throw, not silently pass with a perfect score —
    /// an over-broad mask (e.g. rects given in pixels instead of points) would
    /// otherwise disable a parity test without anyone noticing.
    func testFullyMaskedComparisonThrows() throws {
        let fullMask = [CGRect(origin: .zero, size: ParityFixtureView.pointSize)]
        do {
            _ = try FigmaParity.compare(
                ParityFixtureView(),
                against: referenceName,
                pointSize: ParityFixtureView.pointSize,
                maskRects: fullMask
            )
            XCTFail("a fully-masked comparison must throw, not report a score")
        } catch FigmaParity.ParityError.allPixelsMasked {
            // Expected.
        } catch let FigmaParity.ParityError.referenceMissing(url) {
            throw XCTSkip("Committed self-test reference missing at \(url.path) — regenerate it (see FigmaParityReferences/README.md).")
        }
    }

    /// Record mode: (re)generates the committed reference with the harness's
    /// own renderer. Skips unless FIGMA_PARITY_RECORD=1 is in the test-runner
    /// environment, and fails on purpose after writing so a record run is never
    /// mistaken for a green suite. Inspect the PNG visually before committing.
    func testRecordSelfTestReference() throws {
        // Reading FIGMA_PARITY_RECORD (no prefix) is correct even though the
        // documented command sets TEST_RUNNER_FIGMA_PARITY_RECORD=1: xcodebuild
        // strips the TEST_RUNNER_ prefix and injects the remainder into the
        // test-runner process's environment.
        guard ProcessInfo.processInfo.environment["FIGMA_PARITY_RECORD"] == "1" else {
            throw XCTSkip("Record mode off. Set TEST_RUNNER_FIGMA_PARITY_RECORD=1 to (re)generate the self-test reference.")
        }

        let image = try FigmaParity.render(
            ParityFixtureView(),
            pointSize: ParityFixtureView.pointSize,
            scale: 3
        )
        // Write through the harness's own resolver so the recorded file lands
        // exactly where `compare` will read it (honors FIGMA_PARITY_REFS too).
        let url = FigmaParity.referencesDirectory()
            .appendingPathComponent("\(referenceName).png")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try XCTUnwrap(UIImage(cgImage: image).pngData())
        try data.write(to: url)
        XCTFail("Recorded self-test reference at \(url.path). Inspect it visually, commit it, and re-run without record mode.")
    }

    // MARK: - Helpers

    /// The committed reference makes these tests hermetic; if it has been
    /// deleted locally (e.g. mid-regeneration), skip with instructions instead
    /// of failing on the missing file.
    private func compareOrSkip(_ view: some View) throws -> FigmaParity.Result {
        do {
            return try FigmaParity.compare(
                view,
                against: referenceName,
                pointSize: ParityFixtureView.pointSize
            )
        } catch let FigmaParity.ParityError.referenceMissing(url) {
            throw XCTSkip("Committed self-test reference missing at \(url.path) — regenerate it (see FigmaParityReferences/README.md).")
        }
    }
}
#endif
