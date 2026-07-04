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

    /// MayaChain's inbound entries carry no pause flags at all; nil must read
    /// as not-paused so `halted` remains the only halt signal there.
    func testNilPauseFlagsAreNotHalted() {
        let entry = InboundAddress(
            chain: "ZEC",
            address: "t1RBkNhHAwZcrhN3YmJ9J6f1Jt2QW9dyn1b",
            router: nil,
            halted: false,
            global_trading_paused: nil,
            chain_trading_paused: nil,
            chain_lp_actions_paused: nil,
            gas_rate: "20",
            gas_rate_units: "satsperbyte",
            dust_threshold: "10000",
            outbound_fee: nil,
            outbound_tx_size: nil
        )
        XCTAssertFalse(SwapHaltGate.isHalted(chain: .zcash, in: [entry]))
    }

    /// The exact field set mayanode serves on `/mayachain/inbound_addresses`:
    /// no `router` and none of the THORChain pause flags. Decoding this shape
    /// must succeed — requiring those keys broke the Maya inbound fetch and
    /// with it every Maya-route swap (the ZEC memo path most visibly).
    func testDecodesMayaShapedInboundWithoutPauseFlags() throws {
        let mayaJson = Data("""
        [{
            "chain": "ZEC",
            "pub_key": "mayapub1addwnpepq0000000000000000000000000000000000000000000000000000000000",
            "address": "t1RBkNhHAwZcrhN3YmJ9J6f1Jt2QW9dyn1b",
            "halted": false,
            "gas_rate": "20",
            "gas_rate_units": "satsperbyte",
            "outbound_tx_size": "1000",
            "outbound_fee": "60000",
            "dust_threshold": "10000",
            "observed_fee_rate": "20"
        }]
        """.utf8)

        let decoded = try JSONDecoder().decode([InboundAddress].self, from: mayaJson)

        XCTAssertEqual(decoded.count, 1)
        let entry = try XCTUnwrap(decoded.first)
        XCTAssertEqual(entry.chain, "ZEC")
        XCTAssertFalse(entry.halted)
        XCTAssertNil(entry.global_trading_paused)
        XCTAssertNil(entry.chain_trading_paused)
        XCTAssertNil(entry.chain_lp_actions_paused)
        XCTAssertEqual(entry.gas_rate, "20")
        XCTAssertFalse(SwapHaltGate.isHalted(chain: .zcash, in: decoded))
    }
}
