//
//  SwapKitProviderCacheTests.swift
//  VultisigAppTests
//
//  Eligibility derivation from the `/v3/providers` snapshot — checks chains
//  that have a non-filtered provider enabled, chains that don't, and the
//  THORChain/Maya filter that excludes their entries from the eligibility
//  decision even when their `enabledChainIds` includes the chain.
//

import XCTest
@testable import VultisigApp

final class SwapKitProviderCacheTests: XCTestCase {

    private var providers: [SwapKitProvider] = []

    override func setUpWithError() throws {
        providers = try SwapKitFixtureLoader.decode(
            [SwapKitProvider].self,
            from: "02-providers"
        )
    }

    func testEthereumIsEnabled() {
        XCTAssertTrue(SwapKitProviderCache.chainEnabled(.ethereum, in: providers))
    }

    func testSolanaIsEnabled() {
        XCTAssertTrue(SwapKitProviderCache.chainEnabled(.solana, in: providers))
    }

    /// Phase 2 chain. The cached `/providers` snapshot lists NEAR /
    /// FLASHNET / GARDEN / HARBOR / CHAINFLIP enabling `bitcoin` — none of
    /// those are filtered, so the predicate reports the chain as enabled
    /// for SwapKit.
    func testBitcoinIsEnabled() {
        XCTAssertTrue(SwapKitProviderCache.chainEnabled(.bitcoin, in: providers))
    }

    func testMantleIsNotEnabled() {
        XCTAssertFalse(SwapKitProviderCache.chainEnabled(.mantle, in: providers))
    }

    func testThorchainOnlyChainsAreNotEnabled() {
        // Synthesise a fixture where the only provider enabling a chain is
        // MAYACHAIN_STREAMING. The cache must ignore filtered providers
        // entirely, so the chain reads as "not enabled" even though SwapKit's
        // raw `/v3/providers` response lists it under that provider.
        let synthetic = [
            SwapKitProvider(
                name: "MAYACHAIN_STREAMING",
                provider: "MAYACHAIN_STREAMING",
                displayName: "Maya",
                displayNameLong: "Mayachain Streaming",
                count: 1,
                enabledChainIds: ["cardano"],
                supportedChainIds: ["cardano"],
                supportedActions: ["swap"]
            )
        ]
        XCTAssertFalse(
            SwapKitProviderCache.chainEnabled(.cardano, in: synthetic),
            "Filtered providers must not contribute to eligibility"
        )
    }

    func testNearProviderEnablesSolanaAcrossManyChains() throws {
        let near = try XCTUnwrap(providers.first(where: { $0.name == "NEAR" }))
        XCTAssertTrue(near.enabledChainIds.contains("solana"))
        XCTAssertTrue(near.enabledChainIds.contains("1"))
        XCTAssertTrue(near.enabledChainIds.contains("42161"))
    }
}
