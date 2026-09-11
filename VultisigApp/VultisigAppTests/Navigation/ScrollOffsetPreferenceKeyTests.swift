import SwiftUI
import XCTest
@testable import VultisigApp

final class ScrollOffsetPreferenceKeyTests: XCTestCase {
    func testIdenticalLayoutPassesKeepTheSameOffset() {
        for _ in 0..<20 {
            var value = ScrollOffsetPreferenceKey.defaultValue
            ScrollOffsetPreferenceKey.reduce(value: &value) { -80 }
            XCTAssertEqual(value, -80)
        }
    }

    func testIndependentScrollViewsDoNotSuppressEachOther() {
        var first = ScrollOffsetPreferenceKey.defaultValue
        var second = ScrollOffsetPreferenceKey.defaultValue

        ScrollOffsetPreferenceKey.reduce(value: &first) { -80 }
        ScrollOffsetPreferenceKey.reduce(value: &second) { 125 }

        XCTAssertEqual(first, -80)
        XCTAssertEqual(second, 125)
    }

    func testDefaultValueDoesNotChangeAnExistingOffset() {
        var value: CGFloat = -80

        ScrollOffsetPreferenceKey.reduce(value: &value) { ScrollOffsetPreferenceKey.defaultValue }

        XCTAssertEqual(value, -80)
    }

    func testSiblingOffsetsAreCombinedWithoutDroppingValues() {
        var value = ScrollOffsetPreferenceKey.defaultValue

        ScrollOffsetPreferenceKey.reduce(value: &value) { 12 }
        ScrollOffsetPreferenceKey.reduce(value: &value) { -5 }
        ScrollOffsetPreferenceKey.reduce(value: &value) { 9 }

        XCTAssertEqual(value, 16)
    }
}
