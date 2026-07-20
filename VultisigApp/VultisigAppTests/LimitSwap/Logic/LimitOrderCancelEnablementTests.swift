//
//  LimitOrderCancelEnablementTests.swift
//  VultisigAppTests
//
//  The enablement matrix the detail sheet renders from. Kept on the pure
//  predicate rather than on the view so each arm is asserted directly — a
//  wrongly-enabled Cancel button costs a fee and cancels nothing.
//

import XCTest
@testable import VultisigApp

final class LimitOrderCancelEnablementTests: XCTestCase {

    func testRestingThorchainSourcedOrderIsEnabled() {
        XCTAssertTrue(limitOrderCancelEligibility(makeDetails()).isCancellable)
    }

    func testTerminalOrderIsBlockedRegardlessOfSource() {
        for status in [LimitOrderStatus.filled, .refunded, .expired, .cancelled] {
            XCTAssertEqual(
                limitOrderCancelEligibility(makeDetails(status: status)).blocker,
                .terminal
            )
        }
    }

    /// Terminal wins over every other blocker: a closed order is closed, and
    /// reporting "we can't verify the amounts" about it would be beside the
    /// point.
    func testTerminalTakesPrecedenceOverMissingData() {
        let details = makeDetails(status: .filled, sourceAmount1e8: nil, tradeTarget: nil)

        XCTAssertEqual(limitOrderCancelEligibility(details).blocker, .terminal)
    }

    /// The L1 route has landed: an order funded on a THORChain-routable chain is
    /// cancellable by sending the `m=<` from that chain.
    ///
    /// This replaces the temporary arm that asserted `.notThorchainSourced`,
    /// which was written to fail loudly the moment L1 support arrived. It did.
    func testL1SourcedOrderOnARoutableChainIsCancellable() {
        for chain in [Chain.bitcoin, .ethereum, .dogecoin, .litecoin] {
            XCTAssertTrue(
                limitOrderCancelEligibility(makeDetails(sourceChainRawValue: chain.rawValue)).isCancellable,
                "\(chain.rawValue) source should be cancellable from its own chain"
            )
        }
    }

    /// A chain THORChain cannot route has no inbound vault to send a cancel to.
    func testUnroutableSourceChainIsBlocked() {
        for chain in [Chain.solana, .ton, .polkadot] {
            XCTAssertEqual(
                limitOrderCancelEligibility(makeDetails(sourceChainRawValue: chain.rawValue)).blocker,
                .unsupportedSourceChain,
                "\(chain.rawValue) source"
            )
        }
    }

    /// ⚠️ Nothing in a cancel memo can be shortened, so an ERC20 target from a
    /// UTXO source simply does not fit the 80-byte `OP_RETURN` cap.
    func testErc20TargetFromAUtxoSourceIsBlocked() {
        let details = makeDetails(
            targetAsset: "ETH.USDC-0XA0B86991C6218B36C1D19D4A2E9EB0CE3606EB48",
            sourceChainRawValue: Chain.bitcoin.rawValue
        )

        XCTAssertEqual(limitOrderCancelEligibility(details).blocker, .memoTooLongForSourceChain)
    }

    /// ⚠️ The order is deliberately left `.pending` after a cancel broadcasts,
    /// so `isTerminal` alone would leave the button live and let the user pay
    /// the fee — and on L1 donate the dust — again, for a memo that lands in the
    /// identical ratio bucket.
    func testAnOrderWithACancelAlreadyBroadcastIsBlocked() {
        let details = makeDetails(cancelBroadcastHash: "CANCELTX")

        XCTAssertEqual(limitOrderCancelEligibility(details).blocker, .cancelAlreadyBroadcast)
    }

    /// Terminal still wins: a closed order is closed regardless.
    func testTerminalTakesPrecedenceOverAnOutstandingCancel() {
        let details = makeDetails(status: .filled, cancelBroadcastHash: "CANCELTX")

        XCTAssertEqual(limitOrderCancelEligibility(details).blocker, .terminal)
    }

    func testLegacyOrderWithoutRecordedAmountsIsBlocked() {
        XCTAssertEqual(
            limitOrderCancelEligibility(makeDetails(sourceAmount1e8: nil)).blocker,
            .missingSignedData
        )
        XCTAssertEqual(
            limitOrderCancelEligibility(makeDetails(tradeTarget: nil)).blocker,
            .missingSignedData
        )
        XCTAssertEqual(
            limitOrderCancelEligibility(makeDetails(sourceChainRawValue: nil)).blocker,
            .missingSignedData
        )
    }

    func testQueueDisagreementIsBlocked() {
        XCTAssertEqual(
            limitOrderCancelEligibility(makeDetails(depositAmount: "1")).blocker,
            .signedDataDisagreesWithChain
        )
    }

    /// The memo has to actually build for an order the matrix calls enabled —
    /// otherwise the button appears and the tap silently does nothing.
    func testAnEnabledOrderProducesABuildableMemo() throws {
        guard case let .cancellable(inputs) = limitOrderCancelEligibility(makeDetails()) else {
            return XCTFail("expected cancellable")
        }
        let memo = try buildCancelLimitSwapMemo(inputs)

        XCTAssertTrue(isModifyLimitSwapMemo(memo))
        XCTAssertTrue(memo.hasSuffix(":0"))
    }

    private func makeDetails(
        status: LimitOrderStatus = .pending,
        targetAsset: String = "BTC.BTC",
        depositAmount: String? = nil,
        sourceAmount1e8: String? = "100000000",
        tradeTarget: String? = "15979057441",
        sourceChainRawValue: String? = Chain.thorChain.rawValue,
        cancelBroadcastHash: String? = nil
    ) -> LimitOrderDetails {
        LimitOrderDetails(
            id: "order-1",
            inboundTxHash: "HASH",
            sourceAsset: "THOR.RUNE",
            targetAsset: targetAsset,
            targetPrice: 1,
            expiryBlocks: 14_400,
            createdAt: Date(timeIntervalSince1970: 1_000_000),
            status: status,
            minOutputOverride: nil,
            fill: LimitOrderFill(
                depositAmount: depositAmount,
                filledInAmount: nil,
                filledOutAmount: nil
            ),
            expiry: nil,
            sourceAmount1e8: sourceAmount1e8,
            tradeTarget: tradeTarget,
            observedTradeTarget: nil,
            sourceChainRawValue: sourceChainRawValue,
            cancelBroadcastHash: cancelBroadcastHash
        )
    }
}
