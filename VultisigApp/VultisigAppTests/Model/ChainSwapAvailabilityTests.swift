//
//  ChainSwapAvailabilityTests.swift
//  VultisigApp
//
//  Pins the full truth table of `Chain.isSwapAvailable`. The swap chain
//  picker filters on this property
//  (`SwapCoinPickerView` / `CoinSelectionViewModel`), so any silent flip
//  here changes which chains users can swap. The coverage guard at the
//  bottom forces authors of new `Chain` cases to declare swap
//  availability explicitly rather than relying on a default.
//

@testable import VultisigApp
import XCTest

final class ChainSwapAvailabilityTests: XCTestCase {

    // MARK: - Truth table
    //
    // Hard-coded ledger — every `Chain` case maps to its expected
    // `isSwapAvailable` value. Do NOT derive this from `Chain.allCases`;
    // that would make the test circular. When a new chain ships, the
    // author must add a row here (and the coverage guard below will fail
    // until they do).
    private static let expected: [Chain: Bool] = [
        // Swap-enabled
        .thorChain: true,
        .thorChainChainnet: true,
        .thorChainStagenet: true,
        .mayaChain: true,
        .gaiaChain: true,
        .kujira: true,
        .bitcoin: true,
        .dogecoin: true,
        .bitcoinCash: true,
        .litecoin: true,
        .dash: true,
        .ripple: true,
        .avalanche: true,
        .base: true,
        .bscChain: true,
        .ethereum: true,
        .optimism: true,
        .polygon: true,
        .arbitrum: true,
        .blast: true,
        .cronosChain: true,
        .solana: true,
        .zksync: true,
        .zcash: true,
        .mantle: true,
        .hyperliquid: true,
        .tron: true,
        .cardano: true,
        .sui: true,
        .ton: true,

        // Swap-disabled
        .polygonV2: false,
        .polkadot: false,
        .dydx: false,
        .osmosis: false,
        .terra: false,
        .terraClassic: false,
        .noble: false,
        .akash: false,
        .ethereumSepolia: false,
        .sei: false,
        .qbtc: false,
        .bittensor: false,
    ]

    // MARK: - Per-chain assertions

    func testIsSwapAvailableMatchesTruthTable() {
        for (chain, expectedValue) in Self.expected {
            XCTAssertEqual(
                chain.isSwapAvailable,
                expectedValue,
                "Chain.\(chain) expected isSwapAvailable=\(expectedValue) but got \(chain.isSwapAvailable). " +
                "If this is intentional, update the truth table in ChainSwapAvailabilityTests."
            )
        }
    }

    // MARK: - Coverage guard
    //
    // Forces the truth table to enumerate every `Chain` case. If a new
    // chain is added without updating `expected`, this test fails and
    // the author must declare the new chain's swap availability.

    func testTruthTableCoversEveryChainCase() {
        let covered = Set(Self.expected.keys)
        let all = Set(Chain.allCases)

        let missing = all.subtracting(covered)
        let extra = covered.subtracting(all)

        XCTAssertTrue(
            missing.isEmpty,
            "Chain case(s) missing from the swap-availability truth table: \(missing). " +
            "Add an entry to `expected` declaring whether the new chain ships swap-enabled."
        )
        XCTAssertTrue(
            extra.isEmpty,
            "Truth table references unknown Chain case(s): \(extra)."
        )
        XCTAssertEqual(
            Chain.allCases.count,
            Self.expected.count,
            "Truth table count (\(Self.expected.count)) drifted from Chain.allCases.count (\(Chain.allCases.count))."
        )
    }

    // MARK: - Spot checks: recently enabled chains
    //
    // These exist as standalone tests so a regression of the ADA/TON/SUI
    // flip surfaces with an obvious name in CI failure logs, separate
    // from the generic table-walking test above.

    func testCardanoSwapAvailable() {
        XCTAssertTrue(Chain.cardano.isSwapAvailable)
    }

    func testSuiSwapAvailable() {
        XCTAssertTrue(Chain.sui.isSwapAvailable)
    }

    func testTonSwapAvailable() {
        XCTAssertTrue(Chain.ton.isSwapAvailable)
    }

    // MARK: - Spot checks: Tier 1 L1 sources (DOGE / BCH / LTC / DASH / ZEC / XRP)
    //
    // These light up alongside the Tier 1 L1 sources PR — DOGE/BCH/DASH/ZEC
    // get new per-chain SwapKit signers, LTC ships flag-flip-ready, XRP
    // rides a deposit-only flow through the existing RippleHelper. Standalone
    // tests so a regression of any individual chain's `isSwapAvailable` flag
    // surfaces with an obvious name in CI failure logs.

    func testDogeSwapAvailable() {
        XCTAssertTrue(Chain.dogecoin.isSwapAvailable)
    }

    func testBchSwapAvailable() {
        XCTAssertTrue(Chain.bitcoinCash.isSwapAvailable)
    }

    func testLitecoinSwapAvailable() {
        XCTAssertTrue(Chain.litecoin.isSwapAvailable)
    }

    func testDashSwapAvailable() {
        XCTAssertTrue(Chain.dash.isSwapAvailable)
    }

    func testZcashSwapAvailable() {
        XCTAssertTrue(Chain.zcash.isSwapAvailable)
    }

    func testRippleSwapAvailable() {
        XCTAssertTrue(Chain.ripple.isSwapAvailable)
    }

    // MARK: - Spot checks: chains that must stay disabled
    //
    // Guards against an accidental broad enable (e.g. a refactor that
    // collapses both groups into the `true` branch).

    func testPolygonV2SwapDisabled() {
        XCTAssertFalse(Chain.polygonV2.isSwapAvailable)
    }

    func testPolkadotSwapDisabled() {
        XCTAssertFalse(Chain.polkadot.isSwapAvailable)
    }

    func testDydxSwapDisabled() {
        XCTAssertFalse(Chain.dydx.isSwapAvailable)
    }

    func testOsmosisSwapDisabled() {
        XCTAssertFalse(Chain.osmosis.isSwapAvailable)
    }
}
