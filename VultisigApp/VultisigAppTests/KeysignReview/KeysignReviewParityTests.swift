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
final class KeysignReviewPairCardsTests: XCTestCase {
    func testNotchMoatIsTransparentWithoutACircularCover() throws {
        let renderer = ImageRenderer(content:
            KeysignReviewPairCards(glyph: .chevronRight) {
                Color.clear.frame(height: 80)
            } trailing: {
                Color.clear.frame(height: 80)
            }
            .frame(width: 320)
        )
        try assertTransparentNotch(renderer: renderer, cardFillIsHorizontal: true)
    }

    func testSendAddressCardsHaveTransparentTopAndBottomNotches() throws {
        let renderer = ImageRenderer(content:
            KeysignReviewAddressCards(
                from: KeysignReviewParty(name: "Main Vault", address: "0x1234567890"),
                to: KeysignReviewParty(name: nil, address: "0x0987654321")
            )
            .frame(width: 320)
            .environment(\.dynamicTypeSize, .large)
        )
        try assertTransparentNotch(renderer: renderer, cardFillIsHorizontal: false)
    }

    func testSendBadgeFollowsSeamWithUnequalCardHeights() throws {
        let renderer = ImageRenderer(content:
            KeysignReviewAddressCards(
                from: KeysignReviewParty(name: "Main Vault", address: "0x1234567890"),
                to: KeysignReviewParty(name: nil, address: "0x0987654321")
            )
            .frame(width: 320)
            .environment(\.dynamicTypeSize, .accessibility3)
        )
        try assertTransparentNotch(renderer: renderer, cardFillIsHorizontal: false, expectUnequalHeights: true)
    }

    private func assertTransparentNotch<Content: View>(
        renderer: ImageRenderer<Content>,
        cardFillIsHorizontal: Bool,
        expectUnequalHeights: Bool = false
    ) throws {
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.cgImage)
        let attachment = XCTAttachment(image: UIImage(cgImage: image))
        attachment.name = cardFillIsHorizontal ? "swap-notched-cards" : "send-notched-cards"
        attachment.lifetime = .keepAlways
        add(attachment)
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        try pixels.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(
                data: buffer.baseAddress,
                width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        let midX = width / 2
        let midY: Int
        if cardFillIsHorizontal {
            midY = height / 2
        } else {
            // Away from corners, text and the notch, only the seam is transparent.
            let gapRows = (height / 4..<height * 3 / 4).filter { y in
                pixels[(y * width + 32) * 4 + 3] == 0
            }
            let first = try XCTUnwrap(gapRows.first)
            let last = try XCTUnwrap(gapRows.last)
            midY = (first + last + 1) / 2
            if expectUnequalHeights {
                XCTAssertGreaterThan(abs(midY - height / 2), 8, "Exercise a seam away from the stack center")
            }
        }
        // These points are inside the old 40pt cover but outside the 24pt badge.
        // Checking both the gap and the card cavities catches either workaround.
        for (x, y) in [(midX, midY - 16), (midX, midY + 16), (midX - 15, midY), (midX + 15, midY)] {
            XCTAssertEqual(pixels[(y * width + x) * 4 + 3], 0, "The notch must expose its real background at \(x), \(y)")
        }
        XCTAssertEqual(pixels[(midY * width + midX) * 4 + 3], 255, "Keep the small chevron badge")
        let fillX = width / 4
        let fillY = cardFillIsHorizontal ? midY : height / 4
        XCTAssertEqual(pixels[(fillY * width + fillX) * 4 + 3], 255, "Keep the card fill")
    }
}

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

    func testSwapVerdictMediumMatchesDesign() throws {
        let result = KeysignReviewScanFixture.result(
            .medium,
            description: "This transaction involves a malicious address. Interacting with it may compromise your assets. Proceed only if you are certain."
        )
        try assertReviewParity(
            verdictSheet(title: "swapOverview".localized, result: result),
            reference: "review-swap-verdict-medium",
            height: 411
        )
    }

    func testSwapVerdictMaliciousMatchesDesign() throws {
        let result = KeysignReviewScanFixture.result(
            .critical,
            description: "[TOKEN] has been flagged as malicious by Blockaid. Interacting with it may compromise your assets. Proceed only if you are certain."
        )
        // The same two-line risk title as the send verdict above.
        try assertReviewParity(
            verdictSheet(title: "swapOverview".localized, result: result),
            reference: "review-swap-verdict-malicious",
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
            content: { SendReviewSummaryView(input: summary) },
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

    // MARK: - Swap

    func testSwapUncheckedMatchesDesign() throws {
        try assertReviewParity(swapSheet(isChecked: false, isLimit: true), reference: "review-swap-unchecked", height: 651)
    }

    func testSwapCheckedMatchesDesign() throws {
        try assertReviewParity(swapSheet(isChecked: true, isLimit: false), reference: "review-swap-checked", height: 611)
    }

    /// The design's swap, fees unfolded. The review also keeps what the design
    /// leaves out and these frames do not show: the payout captions under the
    /// destination amount and the quote countdown beside the close button.
    private func swapSheet(isChecked: Bool, isLimit: Bool) -> some View {
        let summary = SwapReviewSummary(
            from: .init(logo: "rune", ticker: "RUNE", chainLogo: nil, amount: "1,000.12", fiat: "$1,203.34", caption: nil, footnote: nil),
            to: .init(logo: "wbtc", ticker: "WBTC", chainLogo: Chain.avalanche.logo, amount: "0.01251", fiat: "$1,203.34", caption: nil, footnote: nil),
            vaultName: "Main Vault",
            vaultAddress: "0xF42jf9840fkfjn38fk0dk9Ac5",
            limitTerms: isLimit ? (targetPrice: "Target Price: 1 BTC = $65,800.13", expiry: "12h") : nil,
            provider: (name: "THORChain", logo: Chain.thorChain.logo),
            slippage: "auto".localized,
            totalFee: "$6.18",
            feeLines: [
                .init(label: "Network Fee", value: "0.04103261 RUNE ($0.08)"),
                .init(label: "Swap Fee (0.5%)", value: "$0.12"),
                .init(label: "Max. Total Fee", value: "$6.18")
            ],
            limitNetworkFee: nil,
            externalRecipient: nil
        )
        let footer = SwapReviewFooter(
            isAmountCorrect: .constant(isChecked),
            isFeeCorrect: .constant(isChecked),
            isApproveCorrect: .constant(false),
            isApproveRequired: false,
            isFastVault: true,
            isSignDisabled: !isChecked,
            onFastSign: {},
            onPairedSign: {}
        )
        return KeysignReviewSheet(
            title: "swapOverview".localized,
            scanRing: KeysignReviewScanRing(.scanned(KeysignReviewScanFixture.result(.noRisk))),
            onClose: {},
            bodyScrolls: false,
            content: { SwapReviewSummaryView(summary: summary) },
            footer: { footer }
        )
    }

    // MARK: - DeFi

    func testDefiBondMatchesDesign() throws {
        try assertReviewParity(defiSheet(ticker: "RUNE", logo: "rune"), reference: "review-defi-bond", height: 571)
    }

    func testDefiStakeMatchesDesign() throws {
        try assertReviewParity(defiSheet(ticker: "TCY", logo: "tcy"), reference: "review-defi-stake", height: 571)
    }

    /// The design's bond and stake frames, which differ only in the coin.
    private func defiSheet(ticker: String, logo: String) -> some View {
        let summary = FunctionTransactionReviewSummary(
            hero: .send(title: "Deposit", coin: HeroCoinAmount(amount: "500", ticker: ticker, logo: logo, fiat: "$1,203.34")),
            vaultName: "Main Vault",
            vaultAddress: "0xF42jf9840fkfjn38fk0dk9Ac5",
            rows: [
                .init(label: "to".localized, value: "thor43jf9840fkfjn38fk0dk9Ac5"),
                .init(label: "network".localized, value: "THORChain", image: Chain.thorChain.logo),
                .init(label: "memo".localized, value: "bond:x/tcy:100000000")
            ],
            fee: (amount: "0.04103261 RUNE", fiat: "$0.08"),
            additionalRows: []
        )
        let footer = SigningCTAButtons(isFastVault: true, onFastSign: {}, onPairedSign: {})
        return KeysignReviewSheet(
            title: "overview".localized,
            scanRing: .hidden,
            onClose: {},
            bodyScrolls: false,
            content: { FunctionTransactionReviewSummaryView(summary: summary) { EmptyView() } },
            footer: { footer }
        )
    }

    // MARK: - Verdict

    private func verdictSheet(title: String, result: SecurityScannerResult) -> some View {
        KeysignReviewSheet(
            title: title,
            scanRing: KeysignReviewScanRing(.scanned(result)),
            scanStatus: .verdict(KeysignReviewVerdict(result: result, onGoBack: {}, onContinueAnyway: {})),
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
