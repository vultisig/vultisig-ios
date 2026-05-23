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

    /// Phase 3 chains. NEAR Intents is enabled on each of these in the
    /// cached `/providers` snapshot; SwapKit routes any of them through
    /// NEAR by default. None of the other Phase 3 source chains have a
    /// non-NEAR provider in the fixture.
    func testTonIsEnabled() {
        XCTAssertTrue(SwapKitProviderCache.chainEnabled(.ton, in: providers))
    }

    func testCardanoIsEnabled() {
        XCTAssertTrue(SwapKitProviderCache.chainEnabled(.cardano, in: providers))
    }

    func testSuiIsEnabled() {
        XCTAssertTrue(SwapKitProviderCache.chainEnabled(.sui, in: providers))
    }

    func testTronIsEnabled() {
        XCTAssertTrue(SwapKitProviderCache.chainEnabled(.tron, in: providers))
    }

    func testMantleIsNotEnabled() {
        XCTAssertFalse(SwapKitProviderCache.chainEnabled(.mantle, in: providers))
    }

    /// Tier 1 L1 chain. NEAR's `enabledChainIds` includes `"dogecoin"` and
    /// `"bitcoincash"` — both are enabled for SwapKit out of the gate.
    func testDogeIsEnabled() {
        XCTAssertTrue(SwapKitProviderCache.chainEnabled(.dogecoin, in: providers))
    }

    func testBitcoinCashIsEnabled() {
        XCTAssertTrue(SwapKitProviderCache.chainEnabled(.bitcoinCash, in: providers))
    }

    func testDashIsEnabled() {
        XCTAssertTrue(SwapKitProviderCache.chainEnabled(.dash, in: providers))
    }

    func testZcashIsEnabled() {
        XCTAssertTrue(SwapKitProviderCache.chainEnabled(.zcash, in: providers))
    }

    func testRippleIsEnabled() {
        XCTAssertTrue(SwapKitProviderCache.chainEnabled(.ripple, in: providers))
    }

    /// LTC is currently NOT in any provider's `enabledChainIds`, so the
    /// cache reads it as "not enabled" and `Coin+Swaps.swift`'s `.litecoin`
    /// arm (which lists `.swapkit`) is silently filtered out at the
    /// `SwapService.fetchSwapKitQuote` gate.
    ///
    /// **Important caveat**: the upstream gate is a false-negative for LTC.
    /// `/v3/quote` actually serves `LTC.LTC → ETH.USDC` routes via NEAR
    /// despite NEAR's `enabledChainIds` omitting `"litecoin"`. We do not
    /// relax the iOS gate here — the eligibility-cache contract is "the
    /// provider says it doesn't serve this chain, don't try" — but the
    /// long-term fix is the LTC source plan
    /// (`pages/projects/vultisig/swapkit-integration/swapkit-ltc-source-plan.md`):
    /// either NEAR fixes its `/v3/providers` metadata or we add a per-chain
    /// override.
    func testLitecoinIsCurrentlyGatedByEnabledChainIds() {
        XCTAssertFalse(
            SwapKitProviderCache.chainEnabled(.litecoin, in: providers),
            "LTC stays gated until NEAR adds `litecoin` to enabledChainIds. " +
            "Gate is overly conservative (live quotes work); see swapkit-ltc-source-plan."
        )
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
