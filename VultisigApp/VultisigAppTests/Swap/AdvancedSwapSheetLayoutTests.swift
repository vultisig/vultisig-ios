//
//  AdvancedSwapSheetLayoutTests.swift
//  VultisigAppTests
//
//  The Advanced Swap sheet's main state is presented at a FIXED detent height,
//  and its content is top-aligned, so nothing about it is self-sizing: every row
//  the card can render, and the inset that keeps the card off the sheet's bottom
//  edge, has to be accounted for in `mainDetentHeight` or the card is either
//  clipped by the sheet edge or left floating in dead space.
//
//  These tests pin that arithmetic for every reachable row combination, and
//  measure the real header / row views to prove the detent still has room for
//  the card and its inset once a row wraps.
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

    /// Every reachable row combination, as
    /// `(isGasLimitSupported, canSelectProvider, isSecuredMint)` with the rows
    /// the card renders and the detent height that has to hold them. A secured
    /// mint never has a Gas Limit row — `isGasLimitSupported` is
    /// `EVM && !isSecuredMint` — so those two are never both true.
    private static let combinations: [(gasLimit: Bool, provider: Bool, securedMint: Bool, rows: Int, height: CGFloat)] = [
        // Non-EVM: Slippage + External Recipient.
        (false, false, false, 2, 276),
        // Non-EVM with a route to pick: + Select route.
        (false, true, false, 3, 346),
        // EVM: + Gas Limit.
        (true, false, false, 3, 346),
        // EVM with a route to pick: every row.
        (true, true, false, 4, 416),
        // Secured mint: Slippage only.
        (false, false, true, 1, 206),
        // Secured mint with a route to pick: + Select route.
        (false, true, true, 2, 276)
    ]

    // MARK: - Row count mirrors the rendered rows

    func testMainRowCountMatchesTheRenderedRowCombinations() {
        for combination in Self.combinations {
            let rows = AdvancedSwapSheet.mainRowCount(
                isGasLimitSupported: combination.gasLimit,
                canSelectProvider: combination.provider,
                isSecuredMint: combination.securedMint
            )
            XCTAssertEqual(rows, combination.rows, "\(combination)")
        }
    }

    // MARK: - Detent height

    /// Only the row count moves between combinations: the chrome and the inset
    /// below the card are the same everywhere, so the card is inset from the
    /// sheet's bottom edge by the same amount whichever rows it renders.
    func testMainDetentHeightGrowsOnlyByTheRowsItRenders() {
        for combination in Self.combinations {
            let height = AdvancedSwapSheet.mainDetentHeight(
                isGasLimitSupported: combination.gasLimit,
                canSelectProvider: combination.provider,
                isSecuredMint: combination.securedMint
            )
            XCTAssertEqual(height, combination.height, accuracy: 0.01, "\(combination)")
        }
    }

    /// The gap under the card mirrors the card's own horizontal inset.
    func testCardInsetMirrorsTheHorizontalInset() {
        XCTAssertEqual(AdvancedSwapSheet.MainLayout.cardInset, 16)
    }

    // MARK: - Measured content fits the detent

    /// The header and the rows are measured as SwiftUI actually lays them out,
    /// so a padding / font change that grows either one fails here instead of
    /// silently pushing the card back under the sheet edge.
    ///
    /// The worst case isn't the tidy one-line row: an External Recipient row
    /// showing a truncated address wraps its title onto a second line (already
    /// true in English on a 375pt phone, and in more locales besides). The
    /// detent has to leave room for the card AND its bottom inset with one of
    /// the rows in that state.
    func testDetentLeavesRoomForTheCardAndItsInsetEvenWhenARowWraps() {
        let headerHeight = measuredHeight(
            of: AdvancedSwapSheetHeader(title: "advancedSwap".localized) {},
            width: sheetWidth
        )
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

        XCTAssertLessThanOrEqual(
            rowHeight,
            AdvancedSwapSheet.MainLayout.rowHeight,
            "A one-line row no longer fits its per-row allowance (measured \(rowHeight)pt)"
        )

        for combination in Self.combinations {
            // Header + the card (rows separated by 1pt hairlines, one of them
            // wrapped) + the inset below the card. The detent sizes the content
            // area, so this has to fit inside it or the card is clipped.
            let separators = CGFloat(combination.rows - 1)
            let content = headerHeight
                + CGFloat(combination.rows - 1) * rowHeight
                + wrappedRowHeight
                + separators
                + AdvancedSwapSheet.MainLayout.cardInset

            XCTAssertLessThanOrEqual(
                content,
                combination.height,
                """
                Content (\(content)pt, one row wrapped) overflows the \(combination.height)pt \
                detent for \(combination) — the card would be clipped by the sheet edge.
                """
            )
        }
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
