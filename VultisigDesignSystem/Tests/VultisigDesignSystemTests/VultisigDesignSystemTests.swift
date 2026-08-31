import SwiftUI
import XCTest
@testable import VultisigDesignSystem

#if canImport(AppKit)
import AppKit
#endif

final class VultisigDesignSystemTests: XCTestCase {
    func testCornerRadiusScaleUsesExpectedPoints() {
        XCTAssertEqual(Theme.radius.xs.points, 4)
        XCTAssertEqual(Theme.radius.sm.points, 8)
        XCTAssertEqual(Theme.radius.md.points, 12)
        XCTAssertEqual(Theme.radius.lg.points, 16)
        XCTAssertEqual(Theme.radius.xl.points, 24)
        XCTAssertEqual(Theme.radius.pill.points, 100_000)
    }

    func testThemeFontsCanBeCreated() {
        _ = Theme.fonts.bodyMMedium
        _ = Theme.fonts.priceBodyS
        _ = Theme.fonts.keypadDigit
    }

    func testThemeColorsCanBeCreated() {
        _ = Theme.colors.bgPrimary
        _ = Theme.colors.textPrimary
        _ = Theme.colors.alertSuccess
        _ = Theme.colors.alertError
    }

    #if canImport(AppKit)
    func testCoreColorsMatchBrandValues() throws {
        let background = try XCTUnwrap(
            NSColor(Theme.colors.bgPrimary).usingColorSpace(.sRGB)
        )
        let positive = try XCTUnwrap(
            NSColor(Theme.colors.alertSuccess).usingColorSpace(.sRGB)
        )

        XCTAssertEqual(background.redComponent, 2.0 / 255, accuracy: 0.001)
        XCTAssertEqual(background.greenComponent, 18.0 / 255, accuracy: 0.001)
        XCTAssertEqual(background.blueComponent, 43.0 / 255, accuracy: 0.001)
        XCTAssertEqual(positive.redComponent, 19.0 / 255, accuracy: 0.001)
        XCTAssertEqual(positive.greenComponent, 200.0 / 255, accuracy: 0.001)
        XCTAssertEqual(positive.blueComponent, 157.0 / 255, accuracy: 0.001)
    }
    #endif
}
