//
//  KeysignReviewParityTests.swift
//  VultisigAppTests
//
//  Compares the review sheet against the design's card exports. The exports
//  are local-only, so these skip wherever FIGMA_PARITY_REFS has none.
//

#if canImport(UIKit)
import SwiftUI
import XCTest
@testable import VultisigApp

@MainActor
final class KeysignReviewParityTests: XCTestCase {
    func testSendVerdictMediumMatchesDesign() throws {
        let result = KeysignReviewScanFixture.result(
            .medium,
            description: "This transaction involves a malicious address. Interacting with it may compromise your assets. Proceed only if you are certain."
        )
        try assertReviewParity(
            verdictSheet(title: "sendOverview".localized, result: result),
            reference: "review-send-verdict-medium",
            height: 411
        )
    }

    func testSendVerdictMaliciousMatchesDesign() throws {
        let result = KeysignReviewScanFixture.result(
            .critical,
            description: "[TOKEN] has been flagged as malicious by Blockaid. Interacting with it may compromise your assets. Proceed only if you are certain."
        )
        // iOS keeps its own risk title, which wraps to two lines where the
        // design's "Malicious token detected" takes one and moves everything
        // under it down a line.
        try assertReviewParity(
            verdictSheet(title: "sendOverview".localized, result: result),
            reference: "review-send-verdict-malicious",
            height: 383,
            perceptualThreshold: 0.93
        )
    }

    // MARK: - Send

    func testSendUncheckedMatchesDesign() throws {
        try assertReviewParity(sendSheet(isChecked: false), reference: "review-send-unchecked", height: 622)
    }

    func testSendCheckedMatchesDesign() throws {
        try assertReviewParity(sendSheet(isChecked: true), reference: "review-send-checked", height: 622)
    }

    /// The design's send: no fiat line under the amount (the review shows one
    /// when a price is known) and a fast vault's two sign buttons.
    private func sendSheet(isChecked: Bool) -> some View {
        let summary = SendCryptoVerifySummary(
            fromName: "Main Vault",
            fromAddress: "0xF43jf9840fkfjn38fk0dk9Ac5",
            toAddress: "0xF43jf9840fkfjn38fk0dk9Ac5",
            network: "THORChain",
            networkImage: Chain.thorChain.logo,
            memo: "send:x/tcy:100000000",
            feeCrypto: "0.04103261 RUNE",
            feeFiat: "$0.08",
            coinImage: Chain.bitcoin.logo,
            amount: "0.025",
            coinTicker: "BTC"
        )
        let footer = sendFooter(isChecked: isChecked)
        return KeysignReviewSheet(
            title: "sendOverview".localized,
            scanRing: .hidden,
            onClose: {},
            bodyScrolls: false,
            content: { SendReviewSummaryView(input: summary, scannerState: .idle) },
            footer: { footer }
        )
    }

    private func sendFooter(isChecked: Bool) -> some View {
        SendReviewFooter(
            isAmountCorrect: .constant(isChecked),
            isAddressCorrect: .constant(isChecked),
            isApproveCorrect: .constant(false),
            isRippleTrustSet: false,
            isApproveRequired: false,
            isFastVault: true,
            isSignDisabled: !isChecked,
            onFastSign: {},
            onPairedSign: {}
        )
    }

    // MARK: - Verdict

    private func verdictSheet(title: String, result: SecurityScannerResult) -> some View {
        KeysignReviewSheet(
            title: title,
            scanRing: KeysignReviewScanRing(.scanned(result)),
            verdict: KeysignReviewVerdict(result: result, onGoBack: {}, onContinueAnyway: {}),
            onClose: {},
            content: { EmptyView() },
            footer: { EmptyView() }
        )
    }
}

/// Renders a review card at the design's 361pt width and compares it with the
/// export, leaving out what the system draws: the rounded corners, which show
/// the dimmed screen behind the card, and the grabber.
@MainActor
func assertReviewParity(
    _ view: some View,
    reference: String,
    height: CGFloat,
    perceptualThreshold: Double = 0.95,
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    let width: CGFloat = 361
    let corner = KeysignReviewSheetLayout.cornerRadius
    let masks = [
        CGRect(x: 0, y: 0, width: corner, height: corner),
        CGRect(x: width - corner, y: 0, width: corner, height: corner),
        CGRect(x: 0, y: height - corner, width: corner, height: corner),
        CGRect(x: width - corner, y: height - corner, width: corner, height: corner),
        CGRect(x: width / 2 - 30, y: 4, width: 60, height: 16)
    ]
    try assertFigmaParity(
        view,
        reference: reference,
        pointSize: CGSize(width: width, height: height),
        scale: 1,
        perceptualThreshold: perceptualThreshold,
        maskRects: masks,
        file: file,
        line: line
    )
}
#endif
