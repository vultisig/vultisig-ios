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

    /// TEMPORARY arm. An L1-funded order is cancellable in principle — by
    /// sending the `m=<` from its own chain — and that path is built later in
    /// this same change. When it lands, this expectation changes from "blocked"
    /// to "cancellable via the L1 route", and this test is the thing that should
    /// fail loudly if the arm is removed without replacing its coverage.
    func testL1SourcedOrderIsBlockedUntilTheL1RouteExists() {
        for chain in [Chain.bitcoin, .ethereum, .dogecoin, .litecoin] {
            XCTAssertEqual(
                limitOrderCancelEligibility(makeDetails(sourceChainRawValue: chain.rawValue)).blocker,
                .notThorchainSourced,
                "\(chain.rawValue) source"
            )
        }
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
        depositAmount: String? = nil,
        sourceAmount1e8: String? = "100000000",
        tradeTarget: String? = "15979057441",
        sourceChainRawValue: String? = Chain.thorChain.rawValue
    ) -> LimitOrderDetails {
        LimitOrderDetails(
            id: "order-1",
            inboundTxHash: "HASH",
            sourceAsset: "THOR.RUNE",
            targetAsset: "BTC.BTC",
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
            sourceChainRawValue: sourceChainRawValue
        )
    }
}
