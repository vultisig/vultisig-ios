//
//  LimitSwapSupportedChainsTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import XCTest

/// Pure `computeSupportedChains` — halt/pause filtering + the static fallback,
/// extracted from the view-model so it no longer depends on
/// `ThorchainService.shared`.
final class LimitSwapSupportedChainsTests: XCTestCase {

    private func inbound(
        chain: String,
        halted: Bool = false,
        globalPaused: Bool? = false,
        chainPaused: Bool? = false
    ) -> InboundAddress {
        InboundAddress(
            chain: chain,
            address: "addr-\(chain)",
            router: nil,
            halted: halted,
            global_trading_paused: globalPaused,
            chain_trading_paused: chainPaused,
            chain_lp_actions_paused: false,
            gas_rate: "0",
            gas_rate_units: "unit",
            dust_threshold: nil,
            outbound_fee: nil,
            outbound_tx_size: nil
        )
    }

    func testIncludesThorChainAndNonHaltedInbounds() {
        let result = computeSupportedChains(from: [inbound(chain: "BTC"), inbound(chain: "ETH")])
        XCTAssertTrue(result.contains(.thorChain))
        XCTAssertTrue(result.contains(.bitcoin))
        XCTAssertTrue(result.contains(.ethereum))
    }

    func testExcludesHaltedChain() {
        let result = computeSupportedChains(from: [
            inbound(chain: "BTC", halted: true),
            inbound(chain: "ETH"),
            inbound(chain: "LTC")
        ])
        XCTAssertFalse(result.contains(.bitcoin), "Halted BTC must be excluded")
        XCTAssertTrue(result.contains(.ethereum))
        XCTAssertTrue(result.contains(.litecoin))
    }

    func testExcludesGloballyPausedAndChainPaused() {
        let result = computeSupportedChains(from: [
            inbound(chain: "BTC", globalPaused: true),
            inbound(chain: "ETH", chainPaused: true),
            inbound(chain: "LTC")
        ])
        XCTAssertFalse(result.contains(.bitcoin))
        XCTAssertFalse(result.contains(.ethereum))
        XCTAssertTrue(result.contains(.litecoin))
    }

    func testIgnoresUnknownChainSymbols() {
        let result = computeSupportedChains(from: [inbound(chain: "BTC"), inbound(chain: "NOTACHAIN")])
        XCTAssertTrue(result.contains(.bitcoin))
        // Unknown symbol contributes nothing; only THOR + BTC remain (>1, no fallback).
        XCTAssertFalse(result.contains(where: { $0 != .thorChain && $0 != .bitcoin }))
    }

    func testFallsBackToStaticSetWhenNoUsefulInbounds() {
        // Empty (or all-halted) inbounds collapse to just {.thorChain}, which
        // triggers the static-prefix-table fallback so the picker isn't empty.
        let empty = computeSupportedChains(from: [])
        XCTAssertTrue(empty.contains(.thorChain))
        XCTAssertTrue(empty.contains(.bitcoin))
        XCTAssertTrue(empty.contains(.ethereum))
        XCTAssertEqual(empty, Set(Chain.allCases.filter { isThorchainRoutable(chain: $0) }))

        let allHalted = computeSupportedChains(from: [
            inbound(chain: "BTC", halted: true),
            inbound(chain: "ETH", halted: true)
        ])
        XCTAssertEqual(allHalted, empty, "All-halted collapses to the same static fallback")
    }
}
