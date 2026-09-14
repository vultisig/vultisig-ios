//
//  TonJettonDiscovererRegistrationTests.swift
//  VultisigAppTests
//

import XCTest
@testable import VultisigApp

@MainActor
final class TonJettonDiscovererRegistrationTests: XCTestCase {

    func testTonResolvesToTheJettonDiscoverer() {
        XCTAssertTrue(TokenDiscovererRegistry.discoverer(for: .ton) is TonJettonTokenDiscoverer)
    }

    /// The other four chains that shared TON's no-op entry keep it. Their
    /// behaviour is out of scope for this change, and several test fixtures
    /// depend on them discovering nothing.
    func testTheOtherNonDiscoveringChainsAreUnchanged() {
        for chain: Chain in [.bitcoin, .litecoin, .cardano, .polkadot, .tron] {
            XCTAssertTrue(
                TokenDiscovererRegistry.discoverer(for: chain) is NoTokenDiscoverer,
                "\(chain.name) must still declare no discovery"
            )
        }
    }

    /// Only a discoverer that matches its results against an address registry
    /// may bypass the spam heuristics; everything else keeps them.
    func testOnlyTheTonDiscovererVouchesForItsResults() {
        XCTAssertTrue(TokenDiscovererRegistry.discoverer(for: .ton).vouchesForResults)

        for chain: Chain in [.ethereum, .solana, .sui, .thorChain, .mayaChain, .ripple, .bitcoin] {
            XCTAssertFalse(
                TokenDiscovererRegistry.discoverer(for: chain).vouchesForResults,
                "\(chain.name) has no address registry to vouch with"
            )
        }
    }
}
