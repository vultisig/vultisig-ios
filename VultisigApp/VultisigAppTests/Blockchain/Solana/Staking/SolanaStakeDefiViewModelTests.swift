//
//  SolanaStakeDefiViewModelTests.swift
//  VultisigAppTests
//
//  Tests the per-stake-account row pipeline: delegated-amount summing into
//  `totalStaked`, activation-state derivation from the live epoch, validator
//  metadata enrichment, APY resolution, and the post-keysign
//  invalidate-and-refresh re-reading stake accounts (which are never cached).
//
//  Also covers the cache-first paint: the VM seeds `rows` synchronously from the
//  persisted Solana `StakePosition` snapshot before any network call, a
//  successful refresh rewrites the snapshot (id-keyed + Solana-scoped
//  delete-stale), and a FAILED stake-account read keeps the last-known snapshot
//  rather than clobbering it with `[]`.
//

@testable import VultisigApp
import Foundation
import SwiftData
import XCTest

// Protocol conformance forces `async throws` the fakes don't await.
// swiftlint:disable async_without_await unused_parameter
private final class FakeStakingService: SolanaStakingServiceProtocol, @unchecked Sendable {
    var accounts: [SolanaStakeAccount]
    var validators: [SolanaValidator]
    var epoch: SolanaEpochInfo
    var inflation: Double
    var rentReserve: UInt64
    /// When set, `fetchStakeAccounts` throws it — simulates an RPC outage.
    var stakeAccountError: Error?

    private(set) var stakeAccountCalls = 0
    private let lock = NSLock()

    init(
        accounts: [SolanaStakeAccount],
        validators: [SolanaValidator] = [],
        epoch: SolanaEpochInfo = SolanaEpochInfo(epoch: 800, slotIndex: 1, slotsInEpoch: 432_000, absoluteSlot: 1),
        inflation: Double = 0.07,
        rentReserve: UInt64 = 2_282_880,
        stakeAccountError: Error? = nil
    ) {
        self.accounts = accounts
        self.validators = validators
        self.epoch = epoch
        self.inflation = inflation
        self.rentReserve = rentReserve
        self.stakeAccountError = stakeAccountError
    }

    func fetchValidators() async throws -> [SolanaValidator] { validators }

    func fetchStakeAccounts(owner: String) async throws -> [SolanaStakeAccount] {
        lock.withLock { stakeAccountCalls += 1 }
        if let stakeAccountError { throw stakeAccountError }
        return accounts
    }

    func fetchEpochInfo() async throws -> SolanaEpochInfo { epoch }
    func fetchRentReserve() async throws -> UInt64 { rentReserve }
    func fetchMinDelegation() async throws -> UInt64 { 1_000_000_000 }
    func fetchInflationRate() async throws -> Double { inflation }
}

/// Counting `SolanaStakingReading` so a test can prove the validator-set cache on
/// a SHARED `SolanaStakingService` survives across freshly-constructed VMs.
private final class CountingReader: SolanaStakingReading, @unchecked Sendable {
    private(set) var validatorCalls = 0
    private let lock = NSLock()

    func fetchSolanaValidators() async throws -> [SolanaValidator] {
        lock.withLock { validatorCalls += 1 }
        return [SolanaValidator(
            votePubkey: "V1", nodePubkey: "Node1", activatedStake: 1,
            commission: 0, epochVoteAccount: true, isDelinquent: false
        )]
    }

    func fetchSolanaStakeAccounts(owner: String) async throws -> [SolanaStakeAccount] { [] }
    func fetchSolanaEpochInfo() async throws -> SolanaEpochInfo {
        SolanaEpochInfo(epoch: 800, slotIndex: 1, slotsInEpoch: 432_000, absoluteSlot: 1)
    }
    func fetchSolanaRentReserve() async throws -> UInt64 { 2_282_880 }
    func fetchSolanaMinDelegation() async throws -> UInt64 { 1_000_000_000 }
    func fetchSolanaInflationRate() async throws -> Double { 0.07 }
}

private struct FakeMetadataProvider: ValidatorMetadataProvider {
    let byVote: [String: ValidatorMetadata]
    func metadata(forVotePubkeys votePubkeys: [String]) async -> [String: ValidatorMetadata] {
        byVote.filter { votePubkeys.contains($0.key) }
    }
}
// swiftlint:enable async_without_await unused_parameter

private enum FakeRPCError: Error { case outage }

@MainActor
final class SolanaStakeDefiViewModelTests: XCTestCase {

    private var storeToken: TestContextToken!
    private var vault: Vault!
    private let storage = DefiPositionsStorageService()
    private let solMeta = CoinMeta.make(chain: .solana, ticker: "SOL", decimals: 9)

    override func setUp() async throws {
        try await super.setUp()
        storeToken = try TestStore.installInMemoryContainer()
        vault = TestStore.makeVault()
        // A SOL native coin so the VM can resolve the CoinMeta it persists into.
        let solCoin = Coin(asset: solMeta, address: "Owner", hexPublicKey: "")
        Storage.shared.modelContext.insert(solCoin)
        solCoin.vault = vault
    }

    override func tearDown() async throws {
        vault = nil
        TestStore.restore(storeToken)
        storeToken = nil
        try await super.tearDown()
    }

    private func makeViewModel(
        service: SolanaStakingServiceProtocol,
        metadata: [String: ValidatorMetadata] = [:]
    ) -> SolanaStakeDefiViewModel {
        SolanaStakeDefiViewModel(
            vault: vault,
            stakingService: service,
            metadataProvider: FakeMetadataProvider(byVote: metadata),
            storage: storage,
            onInvalidateCaches: {}
        )
    }

    private func account(
        pubkey: String,
        vote: String?,
        stake: UInt64,
        activationEpoch: UInt64,
        deactivationEpoch: UInt64 = SolanaStakingConfig.epochSentinel,
        rentReserve: UInt64 = 2_282_880
    ) -> SolanaStakeAccount {
        let delegation = vote.map { v in
            SolanaStakeAccount.Delegation(
                votePubkey: v,
                activationEpoch: activationEpoch,
                deactivationEpoch: deactivationEpoch,
                stake: stake
            )
        }
        return SolanaStakeAccount(
            pubkey: pubkey,
            lamports: stake + rentReserve,
            rentExemptReserve: rentReserve,
            staker: "Owner",
            withdrawer: "Owner",
            delegation: delegation
        )
    }

    private func validator(vote: String, commission: Int, activatedStake: UInt64 = 1_000) -> SolanaValidator {
        SolanaValidator(
            votePubkey: vote,
            nodePubkey: "node-\(vote)",
            activatedStake: activatedStake,
            commission: commission,
            epochVoteAccount: true,
            isDelinquent: false
        )
    }

    private func solanaPositions() -> [StakePosition] {
        vault.stakePositions.filter { $0.coin.chain == .solana }
    }

    func testSumsDelegatedStakeAcrossAccounts() async {
        let lamportsPerSol = Decimal(SolanaStakingConfig.lamportsPerSol)
        let service = FakeStakingService(accounts: [
            account(pubkey: "A", vote: "V1", stake: 2_000_000_000, activationEpoch: 700),
            account(pubkey: "B", vote: "V2", stake: 3_000_000_000, activationEpoch: 700)
        ])
        let vm = makeViewModel(service: service)
        await vm.refresh(owner: "Owner", decimals: 9)
        XCTAssertEqual(vm.rows.count, 2)
        // 2 + 3 = 5 SOL.
        XCTAssertEqual(vm.totalStaked, Decimal(5_000_000_000) / lamportsPerSol)
    }

    func testDerivesActivationStateFromEpoch() async {
        // Current epoch 800. Active: activated < 800, no deactivation.
        // Activating: activated == 800. Deactivating: deactivation >= 800.
        let service = FakeStakingService(accounts: [
            account(pubkey: "Active", vote: "V1", stake: 1_000_000_000, activationEpoch: 700),
            account(pubkey: "Activating", vote: "V2", stake: 1_000_000_000, activationEpoch: 800),
            account(pubkey: "Deactivating", vote: "V3", stake: 1_000_000_000, activationEpoch: 700, deactivationEpoch: 800),
            account(pubkey: "Inactive", vote: "V4", stake: 1_000_000_000, activationEpoch: 700, deactivationEpoch: 700)
        ])
        let vm = makeViewModel(service: service)
        await vm.refresh(owner: "Owner", decimals: 9)
        let byId = Dictionary(uniqueKeysWithValues: vm.rows.map { ($0.id, $0.activationState) })
        XCTAssertEqual(byId["Active"], .active)
        XCTAssertEqual(byId["Activating"], .activating)
        XCTAssertEqual(byId["Deactivating"], .deactivating)
        XCTAssertEqual(byId["Inactive"], .inactive)
    }

    func testGatingFlagsTrackActivationState() async {
        let service = FakeStakingService(accounts: [
            account(pubkey: "Active", vote: "V1", stake: 1_000_000_000, activationEpoch: 700),
            account(pubkey: "Inactive", vote: "V4", stake: 1_000_000_000, activationEpoch: 700, deactivationEpoch: 700)
        ])
        let vm = makeViewModel(service: service)
        await vm.refresh(owner: "Owner", decimals: 9)
        let active = vm.rows.first { $0.id == "Active" }
        let inactive = vm.rows.first { $0.id == "Inactive" }
        XCTAssertEqual(active?.canUnstake, true)
        XCTAssertEqual(active?.canWithdraw, false)
        // A live refresh backs the row, so its actions are enabled.
        XCTAssertEqual(active?.isActionable, true)
        XCTAssertEqual(inactive?.canUnstake, false)
        XCTAssertEqual(inactive?.canWithdraw, true)
    }

    func testEnrichesValidatorNameAndAPYFromMetadata() async {
        let service = FakeStakingService(
            accounts: [account(pubkey: "A", vote: "V1", stake: 1_000_000_000, activationEpoch: 700)],
            validators: [validator(vote: "V1", commission: 5)]
        )
        let vm = makeViewModel(service: service, metadata: [
            "V1": ValidatorMetadata(name: "Vultisig Pool", apyEstimate: Decimal(string: "0.068"))
        ])
        await vm.refresh(owner: "Owner", decimals: 9)
        XCTAssertEqual(vm.rows.first?.validatorName, "Vultisig Pool")
        XCTAssertEqual((vm.rows.first?.apyPercent as NSDecimalNumber?)?.doubleValue ?? 0, 0.068, accuracy: 0.00001)
    }

    func testInvalidateAndRefreshClearsCachesAndReReadsStakeAccounts() async {
        let service = FakeStakingService(accounts: [
            account(pubkey: "A", vote: "V1", stake: 1_000_000_000, activationEpoch: 700)
        ])
        var invalidated = 0
        let vm = SolanaStakeDefiViewModel(
            vault: vault,
            stakingService: service,
            metadataProvider: FakeMetadataProvider(byVote: [:]),
            storage: storage,
            onInvalidateCaches: { invalidated += 1 }
        )
        await vm.refresh(owner: "Owner", decimals: 9)
        await vm.invalidateAndRefresh(owner: "Owner", decimals: 9)
        // Two reads (one per refresh) — stake accounts are never cached — and the
        // cache-invalidation hook fired exactly once on the post-keysign refresh.
        XCTAssertEqual(service.stakeAccountCalls, 2)
        XCTAssertEqual(invalidated, 1)
    }

    // MARK: - Cache-first paint

    /// Seeds a persisted Solana row, then constructs the VM and asserts `rows`
    /// is painted BEFORE any network call (synchronous seed in init).
    func testSeedPaintsPersistedRowsBeforeNetwork() throws {
        try storage.upsert(solanaStake: [
            StakePositionData(
                coin: solMeta,
                type: .stake,
                amount: 4,
                apr: 0.06,
                poolName: "Seeded Validator",
                stakeAccountPubkey: "A",
                validatorVotePubkey: "V1",
                activationState: SolanaStakeActivationState.active.rawValue
            )
        ], for: vault)

        let service = FakeStakingService(accounts: [])
        let vm = makeViewModel(service: service)

        // No refresh yet — the seed must already be on screen.
        XCTAssertEqual(vm.rows.count, 1)
        XCTAssertEqual(vm.rows.first?.id, "A")
        XCTAssertEqual(vm.rows.first?.validatorName, "Seeded Validator")
        XCTAssertEqual(vm.totalStaked, 4)
        // The seed carries no live account, so its actions stay disabled.
        XCTAssertEqual(vm.rows.first?.isActionable, false)
    }

    /// A successful refresh writes the per-account snapshot back to SwiftData.
    func testSuccessfulRefreshUpsertsSnapshot() async {
        let service = FakeStakingService(
            accounts: [account(pubkey: "A", vote: "V1", stake: 1_000_000_000, activationEpoch: 700)],
            validators: [validator(vote: "V1", commission: 5)]
        )
        let vm = makeViewModel(service: service)
        await vm.refresh(owner: "Owner", decimals: 9)

        let persisted = solanaPositions()
        XCTAssertEqual(persisted.count, 1)
        XCTAssertEqual(persisted.first?.stakeAccountPubkey, "A")
        XCTAssertEqual(persisted.first?.validatorVotePubkey, "V1")
        XCTAssertEqual(persisted.first?.activationState, SolanaStakeActivationState.active.rawValue)
        XCTAssertEqual(persisted.first?.amount, 1)
    }

    /// A FAILED stake-account read must keep the last-known seed/rows and the
    /// persisted snapshot — never clobber them with `[]`.
    func testFailedFetchDoesNotClobberSnapshot() async throws {
        try storage.upsert(solanaStake: [
            StakePositionData(
                coin: solMeta,
                type: .stake,
                amount: 9,
                poolName: "Persisted",
                stakeAccountPubkey: "A",
                validatorVotePubkey: "V1",
                activationState: SolanaStakeActivationState.active.rawValue
            )
        ], for: vault)

        let service = FakeStakingService(accounts: [], stakeAccountError: FakeRPCError.outage)
        let vm = makeViewModel(service: service)
        XCTAssertEqual(vm.rows.count, 1) // seeded

        await vm.refresh(owner: "Owner", decimals: 9)

        // Rows unchanged and the persisted row survives the failed read.
        XCTAssertEqual(vm.rows.count, 1)
        XCTAssertEqual(vm.rows.first?.id, "A")
        XCTAssertEqual(solanaPositions().count, 1)
    }

    /// Delete-stale drops a Solana account absent from the fresh read while
    /// leaving a sibling THOR `StakePosition` in the shared relationship intact.
    func testDeleteStaleRemovesAbsentAccountAndKeepsSiblingChain() async throws {
        // Two Solana accounts persisted...
        try storage.upsert(solanaStake: [
            StakePositionData(coin: solMeta, type: .stake, amount: 1, stakeAccountPubkey: "A", activationState: "active"),
            StakePositionData(coin: solMeta, type: .stake, amount: 2, stakeAccountPubkey: "B", activationState: "active")
        ], for: vault)
        // ...plus a sibling THOR stake row sharing `vault.stakePositions`.
        _ = try storage.upsert(stake: [
            StakePositionData(coin: .make(chain: .thorChain, ticker: "RUNE"), type: .stake, amount: 100)
        ], for: vault)
        XCTAssertEqual(vault.stakePositions.count, 3)

        // The fresh read returns only account A — B is gone on chain.
        let service = FakeStakingService(accounts: [
            account(pubkey: "A", vote: "V1", stake: 1_000_000_000, activationEpoch: 700)
        ])
        let vm = makeViewModel(service: service)
        await vm.refresh(owner: "Owner", decimals: 9)

        let solana = solanaPositions()
        XCTAssertEqual(Set(solana.compactMap(\.stakeAccountPubkey)), ["A"], "Absent Solana account deleted.")
        XCTAssertEqual(
            vault.stakePositions.filter { $0.coin.chain == .thorChain }.count,
            1,
            "Sibling THOR stake row must survive Solana-scoped delete-stale."
        )
    }

    /// A shared `SolanaStakingService` keeps its validator-set cache across a
    /// brand-new VM instance — the fix for cold-cache-per-open (VMs are
    /// per-navigation `@StateObject`s that used to news-up their own service).
    func testSharedStakingServiceCacheSurvivesNewViewModel() async {
        let reader = CountingReader()
        let shared = SolanaStakingService(
            solanaService: reader,
            clock: { Date(timeIntervalSince1970: 0) }
        )
        let vm1 = makeViewModel(service: shared)
        await vm1.refresh(owner: "Owner", decimals: 9)

        // A freshly-constructed VM (mimicking navigate-away-then-back) reuses the
        // same shared service — the validator set is NOT refetched.
        let vm2 = makeViewModel(service: shared)
        await vm2.refresh(owner: "Owner", decimals: 9)

        XCTAssertEqual(reader.validatorCalls, 1)
    }
}
