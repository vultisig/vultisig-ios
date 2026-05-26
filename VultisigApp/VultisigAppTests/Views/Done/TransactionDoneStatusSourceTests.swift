//
//  TransactionDoneStatusSourceTests.swift
//  VultisigAppTests
//
//  Contract pins for the `TransactionDoneStatusSource` protocol. The
//  Live (`ChainPollerStatusSource`) implementation is covered indirectly
//  by `TransactionStatusViewModel`'s own tests (it's the wrapped object);
//  what we exercise here is the seam that `DoneScreen` depends on —
//  initial status, `start`/`stop` idempotency, and `StaticStatusSource`
//  emitting its configured status without polling.
//

import XCTest
@testable import VultisigApp

@MainActor
final class TransactionDoneStatusSourceTests: XCTestCase {

    // MARK: - StaticStatusSource

    func testStaticStatusSourceDefaultsToConfirmed() {
        // Cosigner path uses `StaticStatusSource(.confirmed)` because
        // the peer has no broadcast-side identity to drive a live
        // poller — the "Successful" header must appear immediately.
        let source = StaticStatusSource()
        XCTAssertEqual(source.status, .confirmed)
    }

    func testStaticStatusSourceHonorsExplicitStatus() {
        let pending = StaticStatusSource(status: .pending)
        XCTAssertEqual(pending.status, .pending)

        let broadcasted = StaticStatusSource(status: .broadcasted(estimatedTime: "~15 sec"))
        XCTAssertEqual(broadcasted.status, .broadcasted(estimatedTime: "~15 sec"))
    }

    func testStaticStartStopAreNoOps() {
        // `start()` and `stop()` MUST NOT mutate the status — the
        // cosigner header would jitter if they did. They're also
        // safe to call repeatedly (DoneScreen calls start on appear,
        // stop on disappear, and SwiftUI sometimes double-fires).
        let source = StaticStatusSource(status: .confirmed)
        source.start()
        source.start()
        XCTAssertEqual(source.status, .confirmed)
        source.stop()
        source.stop()
        XCTAssertEqual(source.status, .confirmed)
    }

    // MARK: - ChainPollerStatusSource

    func testChainPollerStartsWithBroadcastedStatus() {
        // Pre-poll frame — `TransactionDoneHeaderView` reads the
        // `.broadcasted(estimatedTime:)` copy off the chain config.
        // For an EVM chain that's ~15-30 sec.
        let source = ChainPollerStatusSource(
            txHash: "0xtesthash",
            chain: .ethereum,
            coinTicker: "ETH",
            amount: "1.0 ETH",
            toAddress: "0x0",
            pubKeyECDSA: ""
        )
        guard case .broadcasted = source.status else {
            return XCTFail("Expected .broadcasted status before first poll, got \(source.status)")
        }
    }

    // MARK: - AnyTransactionDoneStatusSourceBox

    func testAnyBoxForwardsStatusFromBoxedSource() {
        // SwapDoneScreen chooses its source at runtime — the box lets
        // it pass either to DoneScreen's `@ObservedObject` slot.
        let inner = StaticStatusSource(status: .confirmed)
        let boxed = AnyTransactionDoneStatusSourceBox(source: inner)
        XCTAssertEqual(boxed.status, .confirmed)
    }
}
