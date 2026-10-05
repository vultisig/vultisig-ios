//
//  MayaLPPreflightTests.swift
//  VultisigAppTests
//
//  mayanode accepts an add inbound, refunds it and keeps the inbound gas when
//  liquidity adds are paused, the chain is halted, or the pool takes no such
//  add. Each rule mirrors the check its add-liquidity handler runs.
//

import XCTest
@testable import VultisigApp

final class MayaLPPreflightTests: XCTestCase {

    private let pool = "BTC.BTC"

    private func evaluate(
        pool: String? = nil,
        isPairedAdd: Bool = true,
        mimir: [String: Int64]? = [:],
        height: Int64? = 1000,
        inbound: InboundAddress? = nil,
        status: String? = "Available"
    ) -> MayaLPPreflightBlock? {
        MayaLPPreflight.evaluate(
            pool: pool ?? self.pool,
            isPairedAdd: isPairedAdd,
            mimir: mimir,
            height: height,
            inbound: inbound,
            poolStatus: status
        )
    }

    func testAHealthyPoolHasNoBlock() {
        XCTAssertNil(evaluate())
    }

    func testAGlobalPauseIsActiveOnceTheChainIsPastItsHeight() {
        XCTAssertEqual(evaluate(mimir: ["PAUSELP": 500]), .lpPaused(pool: pool))
    }

    func testAPauseSetForALaterHeightIsNotYetActive() {
        XCTAssertNil(evaluate(mimir: ["PAUSELP": 2000]))
        XCTAssertNil(evaluate(mimir: ["PAUSELP": 1000]))
    }

    func testAZeroOrMissingKeyDoesNotPause() {
        XCTAssertNil(evaluate(mimir: ["PAUSELP": 0, "PAUSELPETH": 5]))
    }

    func testThePerChainPauseBlocksOnlyThatChainsPools() {
        XCTAssertEqual(evaluate(mimir: ["PAUSELPBTC": 5]), .lpPaused(pool: pool))
        XCTAssertNil(evaluate(mimir: ["PAUSELPETH": 5]))
    }

    /// A failed height read cannot let a configured pause through.
    func testAnUnknownHeightCountsAnySetKeyAsActive() {
        XCTAssertEqual(evaluate(mimir: ["PAUSELP": 99_999], height: nil), .lpPaused(pool: pool))
    }

    func testAnUnreadableMimirFailsOpen() {
        XCTAssertNil(evaluate(mimir: nil))
    }

    func testAHaltedInboundBlocks() {
        let halted = AddLPFixture.inbound(chain: "BTC", address: "x", router: nil, halted: true)
        XCTAssertEqual(evaluate(inbound: halted), .chainHalted(chainPrefix: "BTC"))
    }

    func testAnInboundWithLPActionsPausedBlocks() {
        let paused = AddLPFixture.inbound(chain: "BTC", address: "x", router: nil, lpActionsPaused: true)
        XCTAssertEqual(evaluate(inbound: paused), .chainHalted(chainPrefix: "BTC"))
    }

    func testTheMimirPauseIsReportedBeforeAHaltedChain() {
        let halted = AddLPFixture.inbound(chain: "BTC", address: "x", router: nil, halted: true)
        XCTAssertEqual(evaluate(mimir: ["PAUSELP": 1], inbound: halted), .lpPaused(pool: pool))
    }

    func testASuspendedPoolIsNotAvailable() {
        XCTAssertEqual(evaluate(status: "Suspended"), .poolNotAvailable(pool: pool))
    }

    func testAStagedPoolTakesOnlyPairedAdds() {
        XCTAssertNil(evaluate(isPairedAdd: true, status: "Staged"))
        XCTAssertEqual(evaluate(isPairedAdd: false, status: "Staged"), .stagedPoolRequiresPairedAdd(pool: pool))
    }

    func testAnUnknownPoolStatusFailsOpen() {
        XCTAssertNil(evaluate(status: nil))
    }

    func testThePoolStatusIsReadCaseInsensitively() {
        XCTAssertNil(evaluate(status: "available"))
        XCTAssertEqual(evaluate(isPairedAdd: false, status: "STAGED"), .stagedPoolRequiresPairedAdd(pool: pool))
    }

    func testAMayaNativePoolIgnoresTheInbound() {
        let halted = AddLPFixture.inbound(chain: "MAYA", address: "x", router: nil, halted: true)
        XCTAssertNil(evaluate(pool: "MAYA.MAYA", inbound: halted))
    }
}
