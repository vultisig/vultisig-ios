//
//  TransactionHistoryFailureReasonPresentationTests.swift
//  VultisigAppTests
//

import XCTest
@testable import VultisigApp

final class TransactionHistoryFailureReasonPresentationTests: XCTestCase {
    func testReturnAmountIsNotEnoughUsesSlippageGuidance() {
        XCTAssertEqual(
            TransactionHistoryFailureReasonPresentation.displayText(for: "Return amount is not enough"),
            "swapSlippageToleranceTooTight".localized
        )
    }

    func testInsufficientOutputUsesSlippageGuidance() {
        XCTAssertEqual(
            TransactionHistoryFailureReasonPresentation.displayText(for: "Insufficient output"),
            "swapSlippageToleranceTooTight".localized
        )
    }

    func testReturnAmountSignatureMatchesInsideWrapperText() {
        XCTAssertEqual(
            TransactionHistoryFailureReasonPresentation.displayText(
                for: "RPC error: RETURN AMOUNT IS NOT ENOUGH [code 3]"
            ),
            "swapSlippageToleranceTooTight".localized
        )
    }

    func testMatchingIsCaseInsensitiveInsideWrapperText() {
        XCTAssertEqual(
            TransactionHistoryFailureReasonPresentation.displayText(
                for: "execution reverted: INSUFFICIENT OUTPUT while routing"
            ),
            "swapSlippageToleranceTooTight".localized
        )
    }

    func testUnknownReasonPassesThroughUnchanged() {
        let rawReason = "  execution reverted: transfer failed  "

        XCTAssertEqual(
            TransactionHistoryFailureReasonPresentation.displayText(for: rawReason),
            rawReason
        )
    }

    func testNilAndEmptyReasonsAreSuppressed() {
        XCTAssertNil(TransactionHistoryFailureReasonPresentation.displayText(for: nil))
        XCTAssertNil(TransactionHistoryFailureReasonPresentation.displayText(for: ""))
    }

    // MARK: - Rows

    /// A tracker records a refund as an outcome with no reason; the row still
    /// has to say the funds came back, for native and SwapKit swaps alike.
    func testRefundedSwapRowSaysItWasRefunded() {
        let rows = [
            Self.row(providerKind: NativeSwapTrackingService.providerKind, latest: "refunded"),
            Self.row(providerKind: NativeSwapTrackingService.providerKind, latest: "partially_refunded"),
            Self.row(providerKind: SwapKitTrackingService.providerKind, latest: "refunded"),
            // SwapKit answered with only its coarse status.
            Self.row(providerKind: SwapKitTrackingService.providerKind, latest: nil, coarse: "refunded")
        ]
        for row in rows {
            XCTAssertEqual(
                TransactionHistoryFailureReasonPresentation.displayText(for: row),
                "swapKitStatusRefundedReason".localized,
                row.swapTracking?.latestTrackingStatus ?? "coarse"
            )
        }
    }

    /// The fine-grained status wins when SwapKit sent both, as it does on a
    /// live response; the coarse one fills in only when it is all there is.
    func testCoarseStatusFillsInOnlyWhenTheFineGrainedOneIsMissing() {
        let both = Self.row(providerKind: SwapKitTrackingService.providerKind, latest: "outbound", coarse: "pending")
        XCTAssertEqual(both.swapTrackingUiStatus, .swapping)
        let coarseOnly = Self.row(providerKind: SwapKitTrackingService.providerKind, latest: "", coarse: "completed")
        XCTAssertEqual(coarseOnly.swapTrackingUiStatus, .completed)
        let neither = Self.row(providerKind: SwapKitTrackingService.providerKind, latest: nil)
        XCTAssertEqual(neither.swapTrackingUiStatus, .pending)
    }

    func testStoredReasonIsShownUnchanged() {
        let failed = Self.row(providerKind: NativeSwapTrackingService.providerKind, latest: "failed", errorMessage: "execution reverted")
        XCTAssertEqual(TransactionHistoryFailureReasonPresentation.displayText(for: failed), "execution reverted")

        let untracked = Self.row(providerKind: nil, latest: nil, errorMessage: "Return amount is not enough")
        XCTAssertEqual(
            TransactionHistoryFailureReasonPresentation.displayText(for: untracked),
            "swapSlippageToleranceTooTight".localized
        )
    }

    func testRowsWithoutARefundOrAReasonShowNothing() {
        let rows = [
            Self.row(providerKind: NativeSwapTrackingService.providerKind, latest: "failed"),
            Self.row(providerKind: NativeSwapTrackingService.providerKind, latest: "swapping", status: .inProgress),
            Self.row(providerKind: nil, latest: nil)
        ]
        for row in rows {
            XCTAssertNil(TransactionHistoryFailureReasonPresentation.displayText(for: row))
        }
    }

    /// Limit orders word their own closures (`LimitOrderStatusDisplay`); an
    /// expired or cancelled order refunds too and must not read as a swap refund.
    func testLimitRowIsLeftToItsOwnStatusDisplay() {
        let limit = Self.row(providerKind: THORChainLimitTrackingService.providerKind, latest: "refunded", type: .limit)
        XCTAssertNil(TransactionHistoryFailureReasonPresentation.displayText(for: limit))
    }

    private static func row(
        providerKind: String?,
        latest: String?,
        coarse: String? = nil,
        type: TransactionHistoryType = .swap,
        status: TransactionHistoryStatus = .error,
        errorMessage: String? = nil
    ) -> TransactionHistoryData {
        TransactionHistoryData(
            id: UUID(), txHash: "0xabc", approveTxHash: nil, pubKeyECDSA: "vault", type: type, status: status,
            chainRawValue: Chain.ethereum.rawValue, coinTicker: "ETH", coinLogo: "eth", coinChainLogo: nil,
            amountCrypto: "1", amountFiat: "2000", fromAddress: "from", toAddress: "to",
            toCoinTicker: "BTC", toCoinLogo: "btc", toCoinChainLogo: nil, toAmountCrypto: "0.02",
            toAmountFiat: "2000", swapProvider: "THORChain", feeCrypto: "0", feeFiat: "0",
            network: Chain.ethereum.rawValue, explorerLink: "", createdAt: Date(), completedAt: nil,
            estimatedTime: nil, errorMessage: errorMessage,
            swapTracking: providerKind.map {
                SwapTrackingMetadataData(
                    providerKind: $0,
                    broadcastHash: "0xabc",
                    latestStatus: coarse ?? latest,
                    latestTrackingStatus: latest
                )
            }
        )
    }
}
