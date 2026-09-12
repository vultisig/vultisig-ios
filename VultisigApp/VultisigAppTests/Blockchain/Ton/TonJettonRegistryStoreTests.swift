//
//  TonJettonRegistryStoreTests.swift
//  VultisigAppTests
//

import XCTest
@testable import VultisigApp

final class TonJettonRegistryStoreTests: XCTestCase {

    private let whitelist = TonJettonFixtures.tonAssetsWhitelist

    // MARK: - Merge

    func testRegistryMergesCuratedWithTheWhitelist() async {
        let (store, _) = TonJettonFixtures.store(script: [.success(whitelist)])
        let registry = await store.registry()

        XCTAssertEqual(registry.entry(for: TonJettonFixtures.notcoinMasterRaw)?.symbol, "NOT")
        XCTAssertEqual(
            registry.entry(for: TonJettonFixtures.notcoinMasterRaw)?.verification,
            .verified(source: "ton-assets")
        )
        // Curated is merged in first, so Tether keeps our metadata even though
        // the whitelist also lists that contract.
        let tether = registry.entry(for: TonJettonFixtures.usdtMasterRawUpper)
        XCTAssertEqual(tether?.symbol, "USDT")
        XCTAssertEqual(tether?.decimals, 6)
        XCTAssertEqual(tether?.verification, .curated)
        XCTAssertTrue(registry.impersonates("Tether USD"), "whitelist labels survive the merge")
    }

    // MARK: - Degrade

    func testFetchFailureDegradesToCuratedWithoutThrowing() async {
        let (store, _) = TonJettonFixtures.store(script: [.failure])
        let registry = await store.registry()

        XCTAssertEqual(registry.entry(for: TonJettonFixtures.usdtMasterFriendly)?.symbol, "USDT")
        XCTAssertNil(
            registry.entry(for: TonJettonFixtures.notcoinMasterRaw),
            "A degraded registry recognises fewer jettons, not more"
        )
    }

    func testMalformedPayloadDegradesToCurated() async {
        let (store, _) = TonJettonFixtures.store(script: [.success(TonJettonFixtures.tonAssetsMalformed)])
        let registry = await store.registry()

        XCTAssertEqual(registry.entry(for: TonJettonFixtures.usdtMasterFriendly)?.symbol, "USDT")
        XCTAssertNil(registry.entry(for: TonJettonFixtures.notcoinMasterRaw))
    }

    // MARK: - Caching

    /// The property the issue calls out by name: caching a failure would pin the
    /// degraded registry for the whole TTL, so an outage would keep deciding
    /// which jettons the wallet recognises long after it ended.
    func testFailureIsNotCachedSoTheNextCallRetries() async {
        let (store, client) = TonJettonFixtures.store(script: [.failure, .success(whitelist)])

        let degraded = await store.registry()
        XCTAssertNil(degraded.entry(for: TonJettonFixtures.notcoinMasterRaw))

        let recovered = await store.registry()
        XCTAssertEqual(recovered.entry(for: TonJettonFixtures.notcoinMasterRaw)?.symbol, "NOT")
        XCTAssertEqual(client.attempts, 2, "The outage must be retried, not replayed")
    }

    func testSuccessIsServedFromCacheWithinTheTTL() async {
        let (store, client) = TonJettonFixtures.store(script: [.success(whitelist), .failure])

        _ = await store.registry()
        let second = await store.registry()

        XCTAssertEqual(client.attempts, 1, "A fresh registry must not be refetched")
        XCTAssertEqual(second.entry(for: TonJettonFixtures.notcoinMasterRaw)?.symbol, "NOT")
    }

    func testCacheExpiresAfterTheTTL() async {
        let clock = ManualClock()
        let (store, client) = TonJettonFixtures.store(
            script: [.success(whitelist)],
            ttl: 3600,
            clock: clock
        )

        _ = await store.registry()
        clock.advance(by: 3599)
        _ = await store.registry()
        XCTAssertEqual(client.attempts, 1, "Still fresh one second before the TTL")

        clock.advance(by: 2)
        _ = await store.registry()
        XCTAssertEqual(client.attempts, 2, "Stale past the TTL")
    }

    /// Discovery runs per chain-detail refresh and those fan out several times
    /// after a swap; without coalescing one screen would pull the whole list
    /// repeatedly.
    func testConcurrentCallersShareOneFetch() async {
        let client = ScriptedJettonHTTPClient(script: [.success(whitelist)], delay: .milliseconds(150))
        let (store, _) = TonJettonFixtures.store(script: [], client: client)

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<8 {
                group.addTask { _ = await store.registry() }
            }
        }

        XCTAssertEqual(client.attempts, 1)
    }

    /// A failed batch of concurrent callers must all degrade, and must leave the
    /// store retryable rather than holding a finished, failed task.
    func testConcurrentFailureLeavesTheStoreRetryable() async {
        let client = ScriptedJettonHTTPClient(script: [.failure, .success(whitelist)], delay: .milliseconds(50))
        let (store, _) = TonJettonFixtures.store(script: [], client: client)

        await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<4 {
                group.addTask {
                    await store.registry().entry(for: TonJettonFixtures.notcoinMasterRaw) == nil
                }
            }
            for await degraded in group {
                XCTAssertTrue(degraded, "Every caller in a failed batch degrades")
            }
        }

        let recovered = await store.registry()
        XCTAssertEqual(recovered.entry(for: TonJettonFixtures.notcoinMasterRaw)?.symbol, "NOT")
    }
}
