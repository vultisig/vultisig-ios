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

    // MARK: - Pair predicate (used to disambiguate noRoutesFound)

    /// BCH→ETH is the canonical below-min repro case: NEAR's `enabledChainIds`
    /// includes both `bitcoincash` and `1` on the same provider entry, so the
    /// pair is structurally supported. A `/v3/quote` 404 on this pair therefore
    /// must be amount-driven, which is what the predicate signals.
    func testIsPairSupported_bothChainsInOneProvider_returnsTrue() {
        XCTAssertTrue(
            SwapKitProviderCache.pairEnabled(
                fromChain: .bitcoinCash,
                toChain: .ethereum,
                in: providers
            )
        )
    }

    /// Same provider must enable BOTH chains — union across providers is
    /// intentionally not enough. Synthesise two narrow providers that each
    /// cover one side of the pair and assert the predicate refuses to
    /// classify the pair as supported.
    func testIsPairSupported_chainsSplitAcrossProviders_returnsFalse() {
        let split = [
            SwapKitProvider(
                name: "PROVIDER_A",
                provider: "PROVIDER_A",
                displayName: nil,
                displayNameLong: nil,
                count: 1,
                enabledChainIds: [SwapKitChainIDMapper.swapKitChainId(for: .bitcoinCash)],
                supportedChainIds: nil,
                supportedActions: nil
            ),
            SwapKitProvider(
                name: "PROVIDER_B",
                provider: "PROVIDER_B",
                displayName: nil,
                displayNameLong: nil,
                count: 1,
                enabledChainIds: [SwapKitChainIDMapper.swapKitChainId(for: .ethereum)],
                supportedChainIds: nil,
                supportedActions: nil
            )
        ]
        XCTAssertFalse(
            SwapKitProviderCache.pairEnabled(
                fromChain: .bitcoinCash,
                toChain: .ethereum,
                in: split
            )
        )
    }

    /// Filtered providers (THORChain / MayaChain) must not contribute to the
    /// pair decision. Otherwise the disambiguation would mistakenly classify
    /// pairs only routable through filtered providers as "supported", and
    /// surface "amount too small" tooltips for pairs that have no SwapKit
    /// route at any amount.
    func testIsPairSupported_filteredProviderDoesNotCount() {
        let synthetic = [
            SwapKitProvider(
                name: "MAYACHAIN",
                provider: "MAYACHAIN",
                displayName: nil,
                displayNameLong: nil,
                count: 1,
                enabledChainIds: [
                    SwapKitChainIDMapper.swapKitChainId(for: .bitcoinCash),
                    SwapKitChainIDMapper.swapKitChainId(for: .ethereum)
                ],
                supportedChainIds: nil,
                supportedActions: nil
            )
        ]
        XCTAssertFalse(
            SwapKitProviderCache.pairEnabled(
                fromChain: .bitcoinCash,
                toChain: .ethereum,
                in: synthetic
            )
        )
    }

    /// A chain Vultisig has no SwapKit chain-id mapping for must short-circuit
    /// to `false` — there's no way to verify support, so we don't claim it.
    func testIsPairSupported_unmappedChainReturnsFalse() {
        XCTAssertFalse(
            SwapKitProviderCache.pairEnabled(
                fromChain: .mantle,
                toChain: .ethereum,
                in: providers
            )
        )
    }

    /// Empty snapshot from the async path: the actor's `isPairSupported`
    /// returns `true` as a fail-open default so error reclassification still
    /// fires. The static predicate, used here as a stand-in for "the cache
    /// had no providers to look at", reports `false` for any pair — fail-open
    /// behaviour belongs to the async wrapper, not the pure predicate.
    func testIsPairSupported_emptySnapshotStaticReturnsFalse() {
        XCTAssertFalse(
            SwapKitProviderCache.pairEnabled(
                fromChain: .bitcoinCash,
                toChain: .ethereum,
                in: []
            )
        )
    }

    /// Async fail-OPEN: when the cache has nothing in its snapshot AND the
    /// HTTPClient refuses to fetch, the actor reports the pair as "could be
    /// supported" so the reclassification path still triggers. `isPairSupported`
    /// only chooses between two error labels, so failing it open just keeps the
    /// more specific "amount too small" label available — deliberately the
    /// opposite default from `isEnabled` below.
    func testIsPairSupported_noSnapshotFetchFails_failsOpen() async {
        let cache = SwapKitProviderCache(httpClient: FailingHTTPClient())
        let supported = await cache.isPairSupported(
            fromChain: .bitcoinCash,
            toChain: .ethereum
        )
        XCTAssertTrue(supported)
    }

    // MARK: - Provider gate (isEnabled) — fail-closed on the no-snapshot edge

    /// Async fail-CLOSED: on a cold launch where the first `/providers` fetch
    /// fails and there is no prior snapshot, the gate must report the chain as
    /// NOT enabled. SwapKit is simply not offered until a refresh succeeds,
    /// rather than offering routes that fail downstream. Other providers still
    /// populate the picker and `fetchSwapKitQuote` throws cleanly.
    func testIsEnabled_noSnapshotFetchFails_failsClosed() async {
        let cache = SwapKitProviderCache(httpClient: FailingHTTPClient())
        let enabled = await cache.isEnabled(chain: .ethereum)
        XCTAssertFalse(enabled, "No snapshot + failed fetch must fail closed")
    }

    /// Once a snapshot exists, a later fetch failure must serve the last-good
    /// providers rather than collapsing to fail-closed. Guards against
    /// over-correcting the no-snapshot fix into "any fetch failure disables
    /// SwapKit": seed a snapshot via `setSnapshot`, then drive `isEnabled`
    /// through a failing client past the TTL and assert the chain is still
    /// enabled from the retained snapshot.
    func testIsEnabled_fetchFailsWithPriorSnapshot_servesLastGood() async {
        let cache = SwapKitProviderCache(httpClient: FailingHTTPClient())
        let fetchedAt = Date()
        await cache.setSnapshot(
            SwapKitProvidersSnapshot(providers: providers, fetchedAt: fetchedAt)
        )
        // Advance well past providerCacheTTL so the snapshot is stale and the
        // cache attempts a refresh — which fails — falling back to last-good.
        let later = fetchedAt.addingTimeInterval(SwapKitConfig.providerCacheTTL + 1)
        let enabled = await cache.isEnabled(chain: .ethereum, now: later)
        XCTAssertTrue(enabled, "Stale-but-present snapshot must serve last-good, not fail closed")
    }
}

// MARK: - Test doubles

/// Minimal `HTTPClientProtocol` that always throws — used to prove the cache's
/// fail-open behaviour when there is neither a fresh snapshot nor a fetchable
/// providers list.
private final class FailingHTTPClient: HTTPClientProtocol, @unchecked Sendable {
    private enum TestError: Error { case unavailable }

    func request(_ target: TargetType) async throws -> HTTPResponse<Data> {
        _ = target
        await Task.yield()
        throw TestError.unavailable
    }

    func request<T: Decodable>(_ target: TargetType, responseType: T.Type) async throws -> HTTPResponse<T> {
        _ = target
        _ = responseType
        await Task.yield()
        throw TestError.unavailable
    }
}
