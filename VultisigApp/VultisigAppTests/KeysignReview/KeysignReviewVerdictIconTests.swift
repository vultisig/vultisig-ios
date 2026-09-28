import SwiftUI
import VultisigUIResources
import XCTest
@testable import VultisigApp

@MainActor
final class KeysignReviewVerdictIconTests: XCTestCase {
    func testLowAndMediumRiskUseFigmaCircleWarning() {
        for risk in [SecurityRiskLevel.low, .medium] {
            let icon = makeView(risk).verdictIcon
            XCTAssertEqual(icon.image, .keysignReviewWarning)
            XCTAssertEqual(icon.size, 20)
            XCTAssertEqual(icon.color, Theme.colors.alertWarning)
        }
    }

    func testHighAndCriticalRiskUseFigmaFilledTriangle() {
        for risk in [SecurityRiskLevel.high, .critical] {
            let icon = makeView(risk).verdictIcon
            XCTAssertEqual(icon.image, .keysignReviewDanger)
            XCTAssertEqual(icon.size, 20)
            XCTAssertEqual(icon.color, Theme.colors.alertError)
        }
    }

    #if canImport(UIKit)
    func testFigmaIconsAreBundledAndRenderInVerdicts() throws {
        for (risk, assetName) in [(SecurityRiskLevel.medium, "keysign-review-warning"), (.high, "keysign-review-danger")] {
            let view = makeView(risk)
            XCTAssertNotNil(VultisigResources.platformImage(named: assetName))
            let iconRenderer = ImageRenderer(content: view.verdictIcon)
            iconRenderer.scale = 3
            let icon = try XCTUnwrap(iconRenderer.uiImage)
            XCTAssertEqual(icon.size, CGSize(width: 20, height: 20))
            let image = try XCTUnwrap(icon.cgImage)
            var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
            try pixels.withUnsafeMutableBytes { buffer in
                let context = try XCTUnwrap(CGContext(
                    data: buffer.baseAddress, width: image.width, height: image.height,
                    bitsPerComponent: 8, bytesPerRow: image.width * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ))
                context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            }
            let visiblePixels = stride(from: 3, to: pixels.count, by: 4).filter { pixels[$0] > 0 }.count
            XCTAssertGreaterThan(visiblePixels, 500, "The bundled glyph must not render blank")
            XCTAssertLessThan(visiblePixels, 2500, "Keep the transparent silhouette and exclamation cutouts")
            // Figma's simplified SVG export can fill in the bar while leaving
            // the dot intact. Verify both cutouts in the compiled asset.
            for y in [8, 14] {
                XCTAssertEqual(pixels[((y * 3) * image.width + 30) * 4 + 3], 0,
                               "The exclamation cutout must be transparent at 10, \(y)pt")
            }

            let renderer = ImageRenderer(content: view
                .frame(width: 329)
                .padding(16)
                .background(Theme.colors.bgPrimary)
                .environment(\.dynamicTypeSize, .large)
            )
            renderer.scale = 3
            let attachment = XCTAttachment(image: try XCTUnwrap(renderer.uiImage))
            attachment.name = assetName
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
    #endif

    private func makeView(_ risk: SecurityRiskLevel) -> KeysignReviewVerdictView {
        KeysignReviewVerdictView(verdict: KeysignReviewVerdict(
            result: KeysignReviewScanFixture.result(risk),
            onGoBack: {}, onContinueAnyway: {}
        ))
    }
}
