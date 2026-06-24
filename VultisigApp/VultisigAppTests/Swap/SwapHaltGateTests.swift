//
//  SwapHaltGateTests.swift
//  VultisigAppTests
//
//  The shared inbound-halt resolution used by the sign-time block.
//

import XCTest
@testable import VultisigApp

final class SwapHaltGateTests: XCTestCase {

    private func inbound(
        chain: String,
        halted: Bool = false,
        global: Bool = false,
        chainPaused: Bool = false
    ) -> InboundAddress {
        InboundAddress(
            chain: chain,
            address: "addr",
            router: nil,
            halted: halted,
            global_trading_paused: global,
            chain_trading_paused: chainPaused,
            chain_lp_actions_paused: false,
            gas_rate: "0",
            gas_rate_units: "u",
            dust_threshold: nil,
            outbound_fee: nil,
            outbound_tx_size: nil
        )
    }

    func testHaltedFlagMarksChainHalted() {
        let list = [inbound(chain: "ETH", halted: true)]
        XCTAssertTrue(SwapHaltGate.isHalted(chain: .ethereum, in: list))
    }

    func testGlobalTradingPausedMarksChainHalted() {
        let list = [inbound(chain: "ETH", global: true)]
        XCTAssertTrue(SwapHaltGate.isHalted(chain: .ethereum, in: list))
    }

    func testChainTradingPausedMarksChainHalted() {
        let list = [inbound(chain: "ARB", chainPaused: true)]
        XCTAssertTrue(SwapHaltGate.isHalted(chain: .arbitrum, in: list))
    }

    func testNoFlagsIsNotHalted() {
        let list = [inbound(chain: "ETH")]
        XCTAssertFalse(SwapHaltGate.isHalted(chain: .ethereum, in: list))
    }

    func testMissingChainIsNotHalted() {
        let list = [inbound(chain: "BTC", halted: true)]
        XCTAssertFalse(SwapHaltGate.isHalted(chain: .ethereum, in: list))
    }
}
