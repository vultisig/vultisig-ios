//
//  AdvancedSwapSheetLayoutTests.swift
//  VultisigAppTests
//
//  Measure real rows and preserve the supported visibility combinations.
//

import SwiftUI
import UIKit
import XCTest

@testable import VultisigApp

@MainActor
final class AdvancedSwapSheetLayoutTests: XCTestCase {

    /// A 375pt-wide phone — the narrowest the app runs on, and so the worst case
    /// for intrinsic height, since a narrow row is what makes a title wrap onto
    /// a second line. The card is inset 16pt on each side.
    private let sheetWidth: CGFloat = 375
    private var cardWidth: CGFloat { sheetWidth - 32 }

    /// Preserve the wrapped-row measurement: content must keep its intrinsic
    /// height inside the new scroll view rather than truncate a long label.
    func testRecipientRowGrowsWhenItsLabelWraps() {
        let rowHeight = measuredHeight(
            of: AdvancedSwapMainRow(icon: .bolt, title: "slippageTolerance".localized, value: "auto".localized) {},
            width: cardWidth
        )
        let wrappedRowHeight = measuredHeight(
            of: AdvancedSwapMainRow(
                icon: .clone2,
                title: "useExternalRecipient".localized,
                value: "0x1234…abcd"
            ) {},
            width: cardWidth
        )
        XCTAssertGreaterThan(wrappedRowHeight, rowHeight)
    }

    // MARK: - Helpers

    private func measuredHeight(of view: some View, width: CGFloat) -> CGFloat {
        let controller = UIHostingController(rootView: view.frame(width: width))
        controller.view.backgroundColor = .clear
        return controller.sizeThatFits(
            in: CGSize(width: width, height: .greatestFiniteMagnitude)
        ).height
    }
}
