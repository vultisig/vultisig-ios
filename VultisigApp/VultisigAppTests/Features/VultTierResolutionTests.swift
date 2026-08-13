//
//  VultTierResolutionTests.swift
//  VultisigAppTests
//
//  Covers how a VULT discount tier is put together: the balance half is
//  recomputed on every resolution, while the Thorguard NFT half is the only
//  thing pinned for the session — and only when it was actually determined.
//

import XCTest
@testable import VultisigApp

final class VultTierResolutionTests: XCTestCase {

    // MARK: - Thorguard ownership cache

    /// Pins the optimization the session cache exists for: the Thorguard
    /// `eth_call` must stay off the per-quote critical path.
    func testThorguardOwnershipIsCheckedOncePerVaultPerSession() async {
        let cache = ThorguardOwnershipCache()
        let probe = ThorguardProbe(answers: [true])

        for _ in 0..<5 {
            let owned = await cache.ownsThorguard(for: "vault-a") { await probe.check() }
            XCTAssertEqual(owned, true)
        }

        let callCount = await probe.callCount
        XCTAssertEqual(callCount, 1, "A determined ownership answer must be resolved once per vault per session")
    }

    /// A determined "no NFT" is a real answer and is cached like any other.
    func testDeterminedAbsenceOfTheNftIsCached() async {
        let cache = ThorguardOwnershipCache()
        let probe = ThorguardProbe(answers: [false])

        let first = await cache.ownsThorguard(for: "vault-a") { await probe.check() }
        let second = await cache.ownsThorguard(for: "vault-a") { await probe.check() }

        XCTAssertEqual(first, false)
        XCTAssertEqual(second, false)
        let callCount = await probe.callCount
        XCTAssertEqual(callCount, 1)
    }

    /// A failed `eth_call` is "unknown", not "no NFT". Caching it would strip a
    /// Thorguard holder of their boost for the rest of the session.
    func testUndeterminedOwnershipIsNotCachedAndIsRetried() async {
        let cache = ThorguardOwnershipCache()
        let probe = ThorguardProbe(answers: [nil, true])

        let first = await cache.ownsThorguard(for: "vault-a") { await probe.check() }
        let second = await cache.ownsThorguard(for: "vault-a") { await probe.check() }
        let third = await cache.ownsThorguard(for: "vault-a") { await probe.check() }

        XCTAssertNil(first, "A failed check must surface as unknown")
        XCTAssertEqual(second, true, "The retry's answer must be honoured")
        XCTAssertEqual(third, true, "and then cached like any other determined answer")
        let callCount = await probe.callCount
        XCTAssertEqual(callCount, 2, "Only the failed check is retried")
    }

    /// The warm-up on swap-screen load races the first debounced quote fetch;
    /// they must share one `eth_call` rather than each firing their own.
    func testConcurrentLookupsShareOneCheck() async {
        let cache = ThorguardOwnershipCache()
        let probe = ThorguardProbe(answers: [true], delayNanoseconds: 50_000_000)

        await withTaskGroup(of: Bool?.self) { group in
            for _ in 0..<5 {
                group.addTask {
                    await cache.ownsThorguard(for: "vault-a") { await probe.check() }
                }
            }
            for await owned in group {
                XCTAssertEqual(owned, true)
            }
        }

        let callCount = await probe.callCount
        XCTAssertEqual(callCount, 1, "Concurrent callers for the same vault must share one in-flight check")
    }

    func testOwnershipIsCachedPerVault() async {
        let cache = ThorguardOwnershipCache()
        let probe = ThorguardProbe(answers: [true, false])

        let vaultA = await cache.ownsThorguard(for: "vault-a") { await probe.check() }
        let vaultB = await cache.ownsThorguard(for: "vault-b") { await probe.check() }

        XCTAssertEqual(vaultA, true)
        XCTAssertEqual(vaultB, false, "Switching vaults must resolve fresh, not read the other vault's answer")
        let callCount = await probe.callCount
        XCTAssertEqual(callCount, 2)
    }

    // MARK: - Tier from balance + Thorguard

    func testTierTracksTheBalanceOnEveryResolution() {
        // The first resolution saw nothing, a later one sees the balance that
        // finally landed. Nothing about the first is sticky.
        XCTAssertNil(VultTierService.tier(forBalance: 0, hasThorguard: false))
        XCTAssertEqual(VultTierService.tier(forBalance: 7_500, hasThorguard: false), .gold)
    }

    func testTierUsesTheHighestThresholdMetByTheBalance() {
        XCTAssertNil(VultTierService.tier(forBalance: 1_499, hasThorguard: false))
        XCTAssertEqual(VultTierService.tier(forBalance: 1_500, hasThorguard: false), .bronze)
        XCTAssertEqual(VultTierService.tier(forBalance: 7_499, hasThorguard: false), .silver)
        XCTAssertEqual(VultTierService.tier(forBalance: 7_500, hasThorguard: false), .gold)
        XCTAssertEqual(VultTierService.tier(forBalance: 1_000_000, hasThorguard: false), .ultimate)
    }

    func testThorguardBoostsOneTierAndIsCappedAtPlatinum() {
        XCTAssertEqual(VultTierService.tier(forBalance: 0, hasThorguard: true), .bronze)
        XCTAssertEqual(VultTierService.tier(forBalance: 7_500, hasThorguard: true), .platinum)
        XCTAssertEqual(
            VultTierService.tier(forBalance: 15_000, hasThorguard: true), .platinum,
            "Platinum and above must not be boosted"
        )
        XCTAssertEqual(VultTierService.tier(forBalance: 100_000, hasThorguard: true), .diamond)
    }

    func testUndeterminedOwnershipDoesNotBoostTheTier() {
        XCTAssertEqual(
            VultTierService.tier(forBalance: 7_500, hasThorguard: nil), .gold,
            "An unknown NFT answer must resolve as no boost — the retry lives in the cache, not here"
        )
    }

    // MARK: - Which token counts as VULT

    /// Any address can deploy an ERC-20 under the "VULT" symbol and a user can
    /// add it to their vault. Matching on the ticker let that buy a real
    /// trading-fee discount; the contract address is what actually identifies it.
    @MainActor
    func testImpostorTokenTickeredVultGrantsNoTier() {
        let service = VultTierService()
        let vault = makeVault()
        vault.coins = [makeEthereumToken(ticker: "VULT", contract: "0xdeadbeef00000000000000000000000000000000", balance: 100_000)]

        XCTAssertNil(service.getVultToken(for: vault), "A different contract is a different token, whatever it calls itself")
        let balance = service.getVultToken(for: vault)?.balanceDecimal ?? 0
        XCTAssertNil(
            VultTierService.tier(forBalance: balance, hasThorguard: false),
            "An impostor balance must not unlock any tier"
        )
    }

    @MainActor
    func testRealVultIsMatchedRegardlessOfAddressCasing() {
        let service = VultTierService()
        let vault = makeVault()
        vault.coins = [
            makeEthereumToken(
                ticker: "VULT",
                contract: VultTierService.vultContractAddress.lowercased(),
                balance: 7_500
            )
        ]

        // EIP-55 checksums an address by letter case, so the same token
        // legitimately arrives in different casings.
        let vult = service.getVultToken(for: vault)
        XCTAssertNotNil(vult)
        XCTAssertEqual(VultTierService.tier(forBalance: vult?.balanceDecimal ?? 0, hasThorguard: false), .gold)
    }

    @MainActor
    func testRealVultIsMatchedEvenUnderADifferentTicker() {
        let service = VultTierService()
        let vault = makeVault()
        vault.coins = [
            makeEthereumToken(ticker: "vult", contract: VultTierService.vultContractAddress, balance: 3_000)
        ]

        XCTAssertNotNil(service.getVultToken(for: vault), "The contract is the identity, not the displayed symbol")
    }

    // MARK: - Session-scoped composition

    /// The regression this whole change exists for: the balance half must be
    /// asked again on every resolution while the expensive ownership half is
    /// reused. Caching a resolved tier instead made the first zero balance
    /// permanent, silently dropping the user's fee discount for the session.
    func testSessionResolutionRereadsTheBalanceButChecksOwnershipOnce() async {
        let cache = ThorguardOwnershipCache()
        let ownership = ThorguardProbe(answers: [false])
        let balances = BalanceScript(values: [0, 7_500])

        let first = await VultTierService.resolveSessionTier(
            cache: cache,
            vaultId: "vault-a",
            balance: { await balances.next() },
            ownership: { await ownership.check() }
        )
        let second = await VultTierService.resolveSessionTier(
            cache: cache,
            vaultId: "vault-a",
            balance: { await balances.next() },
            ownership: { await ownership.check() }
        )

        XCTAssertNil(first, "Precondition: the first resolution saw no balance")
        XCTAssertEqual(second, .gold, "A balance that lands late must not be shadowed by the first resolution")
        let reads = await balances.readCount
        XCTAssertEqual(reads, 2, "The balance must be re-read on every resolution")
        let checks = await ownership.callCount
        XCTAssertEqual(checks, 1, "A determined ownership answer must be reused, not re-fetched")
    }

    func testSessionResolutionRetriesAnUndeterminedOwnershipCheck() async {
        let cache = ThorguardOwnershipCache()
        let ownership = ThorguardProbe(answers: [nil, true])
        let balances = BalanceScript(values: [7_500])

        let first = await VultTierService.resolveSessionTier(
            cache: cache,
            vaultId: "vault-a",
            balance: { await balances.next() },
            ownership: { await ownership.check() }
        )
        let second = await VultTierService.resolveSessionTier(
            cache: cache,
            vaultId: "vault-a",
            balance: { await balances.next() },
            ownership: { await ownership.check() }
        )

        XCTAssertEqual(first, .gold, "An undetermined NFT answer must not boost the tier")
        XCTAssertEqual(second, .platinum, "The retried check must be honoured on the next resolution")
        let checks = await ownership.callCount
        XCTAssertEqual(checks, 2)
    }

    /// A vault already at Platinum or above can't be boosted, so the resolution
    /// must not pay for the eth_call at all.
    func testSessionResolutionSkipsTheOwnershipCheckWhenNoBoostIsPossible() async {
        let cache = ThorguardOwnershipCache()
        let ownership = ThorguardProbe(answers: [true])
        let balances = BalanceScript(values: [15_000])

        let tier = await VultTierService.resolveSessionTier(
            cache: cache,
            vaultId: "vault-a",
            balance: { await balances.next() },
            ownership: { await ownership.check() }
        )

        XCTAssertEqual(tier, .platinum)
        let checks = await ownership.callCount
        XCTAssertEqual(checks, 0, "Platinum and above can't be boosted, so no eth_call should be made")
    }

    // MARK: - Fixtures

    @MainActor
    private func makeVault() -> Vault {
        Vault(
            name: "Test Vault",
            signers: [],
            pubKeyECDSA: "test-pub-ecdsa",
            pubKeyEdDSA: "test-pub-eddsa",
            keyshares: [],
            localPartyID: "iPhone-12345",
            hexChainCode: "hex",
            resharePrefix: nil,
            libType: .DKLS
        )
    }

    @MainActor
    private func makeEthereumToken(ticker: String, contract: String, balance: Int) -> Coin {
        let meta = CoinMeta(
            chain: .ethereum,
            ticker: ticker,
            logo: "logo",
            decimals: 18,
            priceProviderId: ticker.lowercased(),
            contractAddress: contract,
            isNativeToken: false
        )
        let coin = Coin(asset: meta, address: "0xwallet", hexPublicKey: "")
        // 18 decimals, so the whole-token balance is the value followed by 18 zeros.
        coin.rawBalance = "\(balance)" + String(repeating: "0", count: 18)
        return coin
    }
}

/// Stand-in for the VULT balance read, answering a scripted sequence and
/// counting how many times the resolution actually asked for it.
private actor BalanceScript {
    private let values: [Decimal]
    private(set) var readCount = 0

    init(values: [Decimal]) {
        self.values = values
    }

    func next() -> Decimal {
        guard !values.isEmpty else { return 0 }
        let value = values[min(readCount, values.count - 1)]
        readCount += 1
        return value
    }
}

/// Stand-in for the Thorguard `eth_call`, answering a scripted sequence and
/// counting how many times it was actually run.
private actor ThorguardProbe {
    private let answers: [Bool?]
    private let delayNanoseconds: UInt64
    private(set) var callCount = 0

    init(answers: [Bool?], delayNanoseconds: UInt64 = 0) {
        self.answers = answers
        self.delayNanoseconds = delayNanoseconds
    }

    func check() async -> Bool? {
        guard !answers.isEmpty else { return nil }
        let index = min(callCount, answers.count - 1)
        callCount += 1
        if delayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
        }
        return answers[index]
    }
}
