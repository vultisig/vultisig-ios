//
//  QBTCClaimEligibilityCheckerTests.swift
//  VultisigAppTests
//
//  Behavior tests for `QBTCClaimEligibilityChecker`. The checker drives
//  the QBTC banner (BTC chain detail) and Claim button (QBTC chain
//  detail) visibility, so these tests lock in the contract: idle/loading
//  transitions, the eligible vs ineligible decision tree, reentrancy,
//  and re-check behaviour.
//

@testable import VultisigApp
import XCTest

@MainActor
final class QBTCClaimEligibilityCheckerTests: XCTestCase {

    // MARK: - Helpers

    /// Real BTC P2WPKH address — 42 chars, `bc1q` prefix. `BtcAddressType.detect`
    /// accepts it so the pipeline doesn't short-circuit on the address-type guard.
    private static let validP2wpkhAddress = "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq"
    private static let secondValidAddress = "bc1q34aq5drpuwy3wgl9lhup9892qp6svr8ldzyy7c"
    private static let unsupportedAddress = "tb1qar0srrr7xfkvy5l643lydnw9re59gtzzdejxsv" // testnet

    private static let utxoA = ClaimableUtxo(
        txid: String(repeating: "a", count: 64), vout: 0, amount: 75_000_000, blockHeight: 1_000_142
    )
    private static let utxoB = ClaimableUtxo(
        txid: String(repeating: "b", count: 64), vout: 1, amount: 25_000_000, blockHeight: 1_000_038
    )
    private static let utxoC = ClaimableUtxo(
        txid: String(repeating: "c", count: 64), vout: 2, amount: 10_000_000, blockHeight: 1_000_007
    )

    private func makeBtcCoin(address: String = QBTCClaimEligibilityCheckerTests.validP2wpkhAddress) -> Coin {
        let asset = CoinMeta(
            chain: .bitcoin,
            ticker: "BTC",
            logo: "BitcoinLogo",
            decimals: 8,
            priceProviderId: "Bitcoin",
            contractAddress: "",
            isNativeToken: true
        )
        return Coin(asset: asset, address: address, hexPublicKey: "hexkey")
    }

    private func makeChecker(
        blockchair: MockBlockchairService = MockBlockchairService(),
        chain: MockQBTCChainService = MockQBTCChainService(),
        cacheStore: UserDefaults? = nil
    ) -> QBTCClaimEligibilityChecker {
        QBTCClaimEligibilityChecker(
            blockchairService: blockchair,
            chainService: chain,
            cacheStore: cacheStore ?? makeIsolatedCacheStore()
        )
    }

    /// Returns a fresh in-memory UserDefaults suite so tests don't read or
    /// pollute each other's cache. The suite is removed in setup of each
    /// test via `removePersistentDomain` to make repeated runs deterministic.
    private func makeIsolatedCacheStore() -> UserDefaults {
        let suiteName = "qbtc-eligibility-tests-\(UUID().uuidString)"
        let store = UserDefaults(suiteName: suiteName) ?? .standard
        store.removePersistentDomain(forName: suiteName)
        return store
    }

    private static let testVaultPubKey = "test-vault-pubkey-ecdsa"

    // MARK: - 1. Idle

    func testIdleStateBeforeCheck() {
        let checker = makeChecker()
        XCTAssertEqual(checker.state, .idle)
        XCTAssertFalse(checker.hasClaimableUtxos)
    }

    // MARK: - 2. Loading (use a gating continuation)

    func testLoadingStateWhileChecking() async {
        let blockchair = MockBlockchairService()
        let chain = MockQBTCChainService()
        let gate = AsyncGate()
        blockchair.fetchHandler = { _, _ in
            await gate.wait()
            return [Self.utxoA]
        }
        let checker = makeChecker(blockchair: blockchair, chain: chain)

        let task = Task { await checker.check(btcCoin: makeBtcCoin(), vaultPubKeyECDSA: Self.testVaultPubKey) }

        // Give the task a chance to enter the pipeline + flip to .loading.
        try? await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(checker.state, .loading)
        XCTAssertFalse(checker.hasClaimableUtxos)

        await gate.open()
        await task.value
        XCTAssertEqual(checker.state, .eligible(count: 1, totalSats: 75_000_000))
    }

    // MARK: - 3. Eligible (utxos present + kill-switch open)

    func testEligibleWhenUtxosPresent() async {
        let blockchair = MockBlockchairService()
        let chain = MockQBTCChainService()
        blockchair.fetchHandler = { _, _ in [Self.utxoA, Self.utxoB, Self.utxoC] }
        let checker = makeChecker(blockchair: blockchair, chain: chain)

        await checker.check(btcCoin: makeBtcCoin(), vaultPubKeyECDSA: Self.testVaultPubKey)

        XCTAssertEqual(checker.state, .eligible(count: 3, totalSats: 110_000_000))
        XCTAssertTrue(checker.hasClaimableUtxos)
        XCTAssertEqual(blockchair.fetchCallCount, 1)
        XCTAssertEqual(chain.filterCallCount, 1)
        XCTAssertEqual(chain.killSwitchCallCount, 1)
    }

    // MARK: - 3b. Ineligible — vault can't run the DKLS claim round (GG20)

    func testIneligibleWhenVaultUnsupported() async {
        let blockchair = MockBlockchairService()
        let chain = MockQBTCChainService()
        blockchair.fetchHandler = { _, _ in [Self.utxoA, Self.utxoB] }
        let checker = makeChecker(blockchair: blockchair, chain: chain)

        await checker.check(
            btcCoin: makeBtcCoin(),
            vaultPubKeyECDSA: Self.testVaultPubKey,
            vaultSupportsClaim: false
        )

        // GG20 vaults short-circuit to ineligible before any network work,
        // so the banner / Claim button never appear and no calls are made.
        XCTAssertEqual(checker.state, .ineligible)
        XCTAssertFalse(checker.hasClaimableUtxos)
        XCTAssertEqual(blockchair.fetchCallCount, 0)
        XCTAssertEqual(chain.killSwitchCallCount, 0)
    }

    // MARK: - 4. Ineligible — no UTXOs at all

    func testIneligibleWhenNoUtxos() async {
        let blockchair = MockBlockchairService()
        let chain = MockQBTCChainService()
        blockchair.fetchHandler = { _, _ in [] }
        let checker = makeChecker(blockchair: blockchair, chain: chain)

        await checker.check(btcCoin: makeBtcCoin(), vaultPubKeyECDSA: Self.testVaultPubKey)

        XCTAssertEqual(checker.state, .ineligible)
        XCTAssertFalse(checker.hasClaimableUtxos)
    }

    // MARK: - 5. Ineligible — filterClaimable drops everything

    func testIneligibleWhenAllFiltered() async {
        let blockchair = MockBlockchairService()
        let chain = MockQBTCChainService()
        blockchair.fetchHandler = { _, _ in [Self.utxoA, Self.utxoB] }
        chain.filterHandler = { _ in [] }
        let checker = makeChecker(blockchair: blockchair, chain: chain)

        await checker.check(btcCoin: makeBtcCoin(), vaultPubKeyECDSA: Self.testVaultPubKey)

        XCTAssertEqual(checker.state, .ineligible)
        XCTAssertEqual(chain.filterCallCount, 1)
    }

    // MARK: - 5b. Confirmation gate — under-confirmed UTXOs are hidden

    /// All UTXOs sit below `MinUtxoConfirmationBlocks` (144) given the tip,
    /// so the gate drops them and the checker reports `.ineligible` — the
    /// banner/Claim button stay hidden instead of promising un-mintable UTXOs.
    func testIneligibleWhenAllUnderConfirmed() async {
        let blockchair = MockBlockchairService()
        let chain = MockQBTCChainService()
        let tip: UInt32 = 1_000_000
        blockchair.tipHeight = tip
        // Both mined within the last few blocks ⇒ << 144 confirmations.
        blockchair.fetchHandler = { _, _ in
            [
                ClaimableUtxo(txid: String(repeating: "a", count: 64), vout: 0, amount: 1_000, blockHeight: tip - 1),
                ClaimableUtxo(txid: String(repeating: "b", count: 64), vout: 1, amount: 2_000, blockHeight: nil)
            ]
        }
        chain.minConfirmationsHandler = { 144 }
        let checker = makeChecker(blockchair: blockchair, chain: chain)

        await checker.check(btcCoin: makeBtcCoin(), vaultPubKeyECDSA: Self.testVaultPubKey)

        XCTAssertEqual(checker.state, .ineligible)
        XCTAssertEqual(chain.minConfirmationsCallCount, 1)
        // The confirmation gate removes every UTXO before the entitlement
        // filter, so `filterClaimable` is invoked once on an empty set — a
        // guarded no-op that makes zero per-UTXO chain queries.
        XCTAssertEqual(chain.filterCallCount, 1)
    }

    /// A confirmed UTXO alongside an under-confirmed one ⇒ only the confirmed
    /// one survives the gate and reaches the eligible rollup.
    func testEligibleKeepsOnlyConfirmedUtxos() async {
        let blockchair = MockBlockchairService()
        let chain = MockQBTCChainService()
        let tip: UInt32 = 1_000_000
        blockchair.tipHeight = tip
        blockchair.fetchHandler = { _, _ in
            [
                // 200 confs — kept.
                ClaimableUtxo(txid: String(repeating: "a", count: 64), vout: 0, amount: 50_000, blockHeight: tip - 199),
                // 10 confs — hidden.
                ClaimableUtxo(txid: String(repeating: "b", count: 64), vout: 1, amount: 99_000, blockHeight: tip - 9)
            ]
        }
        chain.minConfirmationsHandler = { 144 }
        let checker = makeChecker(blockchair: blockchair, chain: chain)

        await checker.check(btcCoin: makeBtcCoin(), vaultPubKeyECDSA: Self.testVaultPubKey)

        XCTAssertEqual(checker.state, .eligible(count: 1, totalSats: 50_000))
    }

    /// If the `MinUtxoConfirmationBlocks` fetch throws, the gate fails open
    /// (keeps all UTXOs) rather than hiding ones the user can see.
    func testConfirmationGateFailsOpenWhenThresholdFetchThrows() async {
        let blockchair = MockBlockchairService()
        let chain = MockQBTCChainService()
        let tip: UInt32 = 1_000_000
        blockchair.tipHeight = tip
        // Under-confirmed, but the threshold fetch fails ⇒ kept anyway.
        blockchair.fetchHandler = { _, _ in
            [ClaimableUtxo(txid: String(repeating: "a", count: 64), vout: 0, amount: 50_000, blockHeight: tip - 1)]
        }
        chain.minConfirmationsHandler = { throw FixtureError.boom }
        let checker = makeChecker(blockchair: blockchair, chain: chain)

        await checker.check(btcCoin: makeBtcCoin(), vaultPubKeyECDSA: Self.testVaultPubKey)

        XCTAssertEqual(checker.state, .eligible(count: 1, totalSats: 50_000))
    }

    // MARK: - 6. Ineligible — kill-switch closed

    func testIneligibleWhenKillSwitchClosed() async {
        let blockchair = MockBlockchairService()
        let chain = MockQBTCChainService()
        chain.killSwitchHandler = { true }
        blockchair.fetchHandler = { _, _ in [Self.utxoA] }
        let checker = makeChecker(blockchair: blockchair, chain: chain)

        await checker.check(btcCoin: makeBtcCoin(), vaultPubKeyECDSA: Self.testVaultPubKey)

        XCTAssertEqual(checker.state, .ineligible)
        // filterClaimable must not run when the kill-switch is closed —
        // the UTXOs would never be claimable on-chain anyway.
        XCTAssertEqual(chain.filterCallCount, 0)
    }

    // MARK: - 7. Ineligible — kill-switch query throws (fail-closed)

    func testIneligibleWhenKillSwitchThrows() async {
        let blockchair = MockBlockchairService()
        let chain = MockQBTCChainService()
        chain.killSwitchHandler = { throw FixtureError.boom }
        blockchair.fetchHandler = { _, _ in [Self.utxoA] }
        let checker = makeChecker(blockchair: blockchair, chain: chain)

        await checker.check(btcCoin: makeBtcCoin(), vaultPubKeyECDSA: Self.testVaultPubKey)

        XCTAssertEqual(checker.state, .ineligible)
    }

    // MARK: - 8. Ineligible — UTXO fetch throws

    func testIneligibleWhenBlockchairThrows() async {
        let blockchair = MockBlockchairService()
        let chain = MockQBTCChainService()
        blockchair.fetchHandler = { _, _ in throw FixtureError.boom }
        let checker = makeChecker(blockchair: blockchair, chain: chain)

        await checker.check(btcCoin: makeBtcCoin(), vaultPubKeyECDSA: Self.testVaultPubKey)

        XCTAssertEqual(checker.state, .ineligible)
    }

    // MARK: - 9. Ineligible — address rejected by BtcAddressType.detect

    func testIneligibleForUnsupportedAddress() async {
        let blockchair = MockBlockchairService()
        let chain = MockQBTCChainService()
        blockchair.fetchHandler = { _, _ in [Self.utxoA] }
        let checker = makeChecker(blockchair: blockchair, chain: chain)

        await checker.check(btcCoin: makeBtcCoin(address: Self.unsupportedAddress), vaultPubKeyECDSA: Self.testVaultPubKey)

        XCTAssertEqual(checker.state, .ineligible)
        // No network calls — the guard short-circuits before the pipeline.
        XCTAssertEqual(blockchair.fetchCallCount, 0)
        XCTAssertEqual(chain.killSwitchCallCount, 0)
        XCTAssertEqual(chain.filterCallCount, 0)
    }

    // MARK: - 10. Reentrancy: two near-simultaneous checks share one task

    func testReentrancyIsNoOpWhileLoading() async {
        let blockchair = MockBlockchairService()
        let chain = MockQBTCChainService()
        let gate = AsyncGate()
        blockchair.fetchHandler = { _, _ in
            await gate.wait()
            return [Self.utxoA]
        }
        let checker = makeChecker(blockchair: blockchair, chain: chain)

        let first = Task { await checker.check(btcCoin: makeBtcCoin(), vaultPubKeyECDSA: Self.testVaultPubKey) }
        try? await Task.sleep(nanoseconds: 20_000_000)
        let second = Task { await checker.check(btcCoin: makeBtcCoin(), vaultPubKeyECDSA: Self.testVaultPubKey) }

        // Both awaits are pending; release the gate and let both finish.
        await gate.open()
        await first.value
        await second.value

        // Only one underlying network round-trip happened.
        XCTAssertEqual(blockchair.fetchCallCount, 1)
        XCTAssertEqual(chain.killSwitchCallCount, 1)
        XCTAssertEqual(checker.state, .eligible(count: 1, totalSats: 75_000_000))
    }

    // MARK: - 11. Re-check after completion runs fresh pipeline

    func testRecheckAfterCompletion() async {
        let blockchair = MockBlockchairService()
        let chain = MockQBTCChainService()
        var nextUtxos: [ClaimableUtxo] = [Self.utxoA]
        blockchair.fetchHandler = { _, _ in nextUtxos }
        let checker = makeChecker(blockchair: blockchair, chain: chain)

        await checker.check(btcCoin: makeBtcCoin(), vaultPubKeyECDSA: Self.testVaultPubKey)
        XCTAssertEqual(checker.state, .eligible(count: 1, totalSats: 75_000_000))

        // Simulate the UTXO being spent / claimed between checks.
        nextUtxos = []
        await checker.check(btcCoin: makeBtcCoin(), vaultPubKeyECDSA: Self.testVaultPubKey)
        XCTAssertEqual(checker.state, .ineligible)
        XCTAssertEqual(blockchair.fetchCallCount, 2)
    }

    // MARK: - 12. Address change re-runs check

    func testAddressChangeReRunsCheck() async {
        let blockchair = MockBlockchairService()
        let chain = MockQBTCChainService()
        blockchair.fetchHandler = { _, _ in [Self.utxoA] }
        let checker = makeChecker(blockchair: blockchair, chain: chain)

        await checker.check(btcCoin: makeBtcCoin(address: Self.validP2wpkhAddress), vaultPubKeyECDSA: Self.testVaultPubKey)
        XCTAssertEqual(checker.state, .eligible(count: 1, totalSats: 75_000_000))

        await checker.check(btcCoin: makeBtcCoin(address: Self.secondValidAddress), vaultPubKeyECDSA: Self.testVaultPubKey)
        XCTAssertEqual(checker.state, .eligible(count: 1, totalSats: 75_000_000))
        XCTAssertEqual(blockchair.fetchCallCount, 2)
    }

    // MARK: - 13. Cache: previously-eligible seeds state immediately

    /// First checker writes the cache; second checker (same vault + address,
    /// same in-memory UserDefaults suite) hydrates `state == .eligible`
    /// synchronously in `check()`, before the network round-trip lands.
    func testCachedEligibleSeedsStateImmediately() async {
        let store = makeIsolatedCacheStore()

        let firstBlockchair = MockBlockchairService()
        let firstChain = MockQBTCChainService()
        firstBlockchair.fetchHandler = { _, _ in [Self.utxoA, Self.utxoB] }
        let firstChecker = makeChecker(blockchair: firstBlockchair, chain: firstChain, cacheStore: store)
        await firstChecker.check(btcCoin: makeBtcCoin(), vaultPubKeyECDSA: Self.testVaultPubKey)
        XCTAssertEqual(firstChecker.state, .eligible(count: 2, totalSats: 100_000_000))

        // Second checker — same cache store, second instance. It should
        // surface the cached eligible state *before* the network refresh
        // resolves, eliminating the idle/loading flicker.
        let secondBlockchair = MockBlockchairService()
        let secondChain = MockQBTCChainService()
        let gate = AsyncGate()
        secondBlockchair.fetchHandler = { _, _ in
            await gate.wait()
            return [Self.utxoA, Self.utxoB]
        }
        let secondChecker = makeChecker(blockchair: secondBlockchair, chain: secondChain, cacheStore: store)

        let task = Task { await secondChecker.check(btcCoin: makeBtcCoin(), vaultPubKeyECDSA: Self.testVaultPubKey) }

        // Yield once so check()'s synchronous prologue runs.
        try? await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(secondChecker.state, .eligible(count: 2, totalSats: 100_000_000))
        XCTAssertTrue(secondChecker.hasClaimableUtxos)

        await gate.open()
        await task.value
    }

    // MARK: - 14. Cache: definitive ineligible clears the entry

    /// After an .eligible run, a subsequent .ineligible outcome (e.g.
    /// user spent UTXOs externally) clears the cache. A third checker
    /// starts at .loading rather than .eligible.
    func testIneligibleOutcomeClearsCache() async {
        let store = makeIsolatedCacheStore()

        let firstChecker = makeChecker(
            blockchair: { let m = MockBlockchairService(); m.fetchHandler = { _, _ in [Self.utxoA] }; return m }(),
            chain: MockQBTCChainService(),
            cacheStore: store
        )
        await firstChecker.check(btcCoin: makeBtcCoin(), vaultPubKeyECDSA: Self.testVaultPubKey)
        XCTAssertEqual(firstChecker.state, .eligible(count: 1, totalSats: 75_000_000))

        let secondChecker = makeChecker(
            blockchair: { let m = MockBlockchairService(); m.fetchHandler = { _, _ in [] }; return m }(),
            chain: MockQBTCChainService(),
            cacheStore: store
        )
        await secondChecker.check(btcCoin: makeBtcCoin(), vaultPubKeyECDSA: Self.testVaultPubKey)
        XCTAssertEqual(secondChecker.state, .ineligible)

        // Third checker — cache should be cleared, so it starts in
        // .loading (no synchronous seed) until its own pipeline lands.
        let gate = AsyncGate()
        let thirdBlockchair = MockBlockchairService()
        thirdBlockchair.fetchHandler = { _, _ in
            await gate.wait()
            return []
        }
        let thirdChecker = makeChecker(blockchair: thirdBlockchair, chain: MockQBTCChainService(), cacheStore: store)

        let task = Task { await thirdChecker.check(btcCoin: makeBtcCoin(), vaultPubKeyECDSA: Self.testVaultPubKey) }
        try? await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(thirdChecker.state, .loading)

        await gate.open()
        await task.value
    }

    // MARK: - 15. Cache: transient network error preserves cached state

    /// A network failure during the refresh leaves the cached .eligible
    /// state untouched. Banner doesn't flicker out because of a hiccup.
    func testNetworkErrorPreservesCachedEligible() async {
        let store = makeIsolatedCacheStore()

        let firstBlockchair = MockBlockchairService()
        firstBlockchair.fetchHandler = { _, _ in [Self.utxoA] }
        let firstChecker = makeChecker(blockchair: firstBlockchair, chain: MockQBTCChainService(), cacheStore: store)
        await firstChecker.check(btcCoin: makeBtcCoin(), vaultPubKeyECDSA: Self.testVaultPubKey)
        XCTAssertEqual(firstChecker.state, .eligible(count: 1, totalSats: 75_000_000))

        let secondBlockchair = MockBlockchairService()
        secondBlockchair.fetchHandler = { _, _ in throw FixtureError.boom }
        let secondChecker = makeChecker(blockchair: secondBlockchair, chain: MockQBTCChainService(), cacheStore: store)
        await secondChecker.check(btcCoin: makeBtcCoin(), vaultPubKeyECDSA: Self.testVaultPubKey)

        // Pipeline threw — but the cache hydration kept state at
        // .eligible. Banner stays visible.
        XCTAssertEqual(secondChecker.state, .eligible(count: 1, totalSats: 75_000_000))
    }

    // MARK: - 16. Cache: different vaults are isolated

    /// Cache key is scoped by vaultPubKeyECDSA. A second vault on the
    /// same machine doesn't see the first vault's cached state.
    func testCacheIsolatedByVault() async {
        let store = makeIsolatedCacheStore()

        let blockchair = MockBlockchairService()
        blockchair.fetchHandler = { _, _ in [Self.utxoA] }
        let firstChecker = makeChecker(blockchair: blockchair, chain: MockQBTCChainService(), cacheStore: store)
        await firstChecker.check(btcCoin: makeBtcCoin(), vaultPubKeyECDSA: "vault-a")
        XCTAssertEqual(firstChecker.state, .eligible(count: 1, totalSats: 75_000_000))

        // Second vault — same store, different key. State starts at
        // .loading until its own pipeline resolves.
        let gate = AsyncGate()
        let secondBlockchair = MockBlockchairService()
        secondBlockchair.fetchHandler = { _, _ in
            await gate.wait()
            return [Self.utxoA]
        }
        let secondChecker = makeChecker(blockchair: secondBlockchair, chain: MockQBTCChainService(), cacheStore: store)

        let task = Task { await secondChecker.check(btcCoin: makeBtcCoin(), vaultPubKeyECDSA: "vault-b") }
        try? await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(secondChecker.state, .loading)

        await gate.open()
        await task.value
    }
}

// MARK: - Fixtures

private enum FixtureError: Error { case boom }

/// One-shot gate for blocking inside a mock handler until the test
/// releases it. Lets us assert `.loading` while a `check()` is in flight.
private actor AsyncGate {
    private var opened = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if opened { return }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            waiters.append(cont)
        }
    }

    func open() {
        opened = true
        let toResume = waiters
        waiters.removeAll()
        for cont in toResume { cont.resume() }
    }
}

private final class MockBlockchairService: BlockchairServiceClaimable, @unchecked Sendable {
    /// Handler still returns just the UTXOs to keep existing tests terse;
    /// the conformance wraps them with `tipHeight`. Default tip is far above
    /// the fixtures' block heights so they stay confirmed unless a test
    /// overrides it.
    var fetchHandler: @Sendable (CoinMeta, String) async throws -> [ClaimableUtxo] = { _, _ in [] }
    var tipHeight: UInt32? = 9_000_000
    private let lock = NSLock()
    private var _fetchCallCount = 0
    var fetchCallCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _fetchCallCount
    }

    func fetchQBTCClaimableUtxos(bitcoinCoin: CoinMeta, address: String) async throws -> QBTCClaimableUtxosResult {
        lock.lock(); _fetchCallCount += 1; lock.unlock()
        let utxos = try await fetchHandler(bitcoinCoin, address)
        return QBTCClaimableUtxosResult(utxos: utxos, btcTipHeight: tipHeight)
    }
}

private final class MockQBTCChainService: QBTCChainServiceClaimable, @unchecked Sendable {
    var filterHandler: @Sendable ([ClaimableUtxo]) async -> [ClaimableUtxo] = { $0 }
    var killSwitchHandler: @Sendable () async throws -> Bool = { false }
    /// Default low threshold so the fixtures (≈3M+ confirmations against the
    /// mock tip) pass the gate. Override to exercise under-confirmed paths.
    var minConfirmationsHandler: @Sendable () async throws -> UInt32 = { 6 }
    private let lock = NSLock()
    private var _filterCallCount = 0
    private var _killSwitchCallCount = 0
    private var _minConfirmationsCallCount = 0

    var filterCallCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _filterCallCount
    }

    var killSwitchCallCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _killSwitchCallCount
    }

    var minConfirmationsCallCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _minConfirmationsCallCount
    }

    func filterClaimable(_ utxos: [ClaimableUtxo]) async -> [ClaimableUtxo] {
        lock.lock(); _filterCallCount += 1; lock.unlock()
        return await filterHandler(utxos)
    }

    func isClaimWithProofDisabled() async throws -> Bool {
        lock.lock(); _killSwitchCallCount += 1; lock.unlock()
        return try await killSwitchHandler()
    }

    func minUtxoConfirmationBlocks() async throws -> UInt32 {
        lock.lock(); _minConfirmationsCallCount += 1; lock.unlock()
        return try await minConfirmationsHandler()
    }

    /// Delegates to the real pure confirmation math so the gate behaviour
    /// under test matches production.
    func filterSufficientlyConfirmed(
        _ utxos: [ClaimableUtxo],
        btcTipHeight: UInt32?,
        minConfirmations: UInt32
    ) -> [ClaimableUtxo] {
        guard let btcTipHeight else { return utxos }
        return utxos.filter {
            QBTCChainService.confirmations(blockHeight: $0.blockHeight, tipHeight: btcTipHeight) >= minConfirmations
        }
    }
}
