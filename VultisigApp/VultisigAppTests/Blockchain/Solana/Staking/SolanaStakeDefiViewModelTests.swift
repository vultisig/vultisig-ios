//
//  SolanaStakeDefiViewModelTests.swift
//  VultisigAppTests
//
//  Tests the per-stake-account row pipeline: delegated-amount summing into
//  `totalStaked`, activation-state derivation from the live epoch, validator
//  metadata enrichment, APY resolution, and the post-keysign
//  invalidate-and-refresh re-reading stake accounts (which are never cached).
//

@testable import VultisigApp
import Foundation
import XCTest

// Protocol conformance forces `async throws` the fakes don't await.
// swiftlint:disable async_without_await unused_parameter
private final class FakeStakingService: SolanaStakingServiceProtocol, @unchecked Sendable {
    var accounts: [SolanaStakeAccount]
    var validators: [SolanaValidator]
    var epoch: SolanaEpochInfo
    var inflation: Double
    var rentReserve: UInt64

    private(set) var stakeAccountCalls = 0
    private let lock = NSLock()

    init(
        accounts: [SolanaStakeAccount],
        validators: [SolanaValidator] = [],
        epoch: SolanaEpochInfo = SolanaEpochInfo(epoch: 800, slotIndex: 1, slotsInEpoch: 432_000, absoluteSlot: 1),
        inflation: Double = 0.07,
        rentReserve: UInt64 = 2_282_880
    ) {
        self.accounts = accounts
        self.validators = validators
        self.epoch = epoch
        self.inflation = inflation
        self.rentReserve = rentReserve
    }

    func fetchValidators() async throws -> [SolanaValidator] { validators }

    func fetchStakeAccounts(owner: String) async throws -> [SolanaStakeAccount] {
        lock.withLock { stakeAccountCalls += 1 }
        return accounts
    }

    func fetchEpochInfo() async throws -> SolanaEpochInfo { epoch }
    func fetchRentReserve() async throws -> UInt64 { rentReserve }
    func fetchInflationRate() async throws -> Double { inflation }
}

private struct FakeMetadataProvider: ValidatorMetadataProvider {
    let byVote: [String: ValidatorMetadata]
    func metadata(forVotePubkeys votePubkeys: [String]) async -> [String: ValidatorMetadata] {
        byVote.filter { votePubkeys.contains($0.key) }
    }
}
// swiftlint:enable async_without_await unused_parameter

@MainActor
final class SolanaStakeDefiViewModelTests: XCTestCase {

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

    func testSumsDelegatedStakeAcrossAccounts() async {
        let lamportsPerSol = Decimal(SolanaStakingConfig.lamportsPerSol)
        let service = FakeStakingService(accounts: [
            account(pubkey: "A", vote: "V1", stake: 2_000_000_000, activationEpoch: 700),
            account(pubkey: "B", vote: "V2", stake: 3_000_000_000, activationEpoch: 700)
        ])
        let vm = SolanaStakeDefiViewModel(
            stakingService: service,
            metadataProvider: FakeMetadataProvider(byVote: [:]),
            onInvalidateCaches: {}
        )
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
        let vm = SolanaStakeDefiViewModel(
            stakingService: service,
            metadataProvider: FakeMetadataProvider(byVote: [:]),
            onInvalidateCaches: {}
        )
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
        let vm = SolanaStakeDefiViewModel(
            stakingService: service,
            metadataProvider: FakeMetadataProvider(byVote: [:]),
            onInvalidateCaches: {}
        )
        await vm.refresh(owner: "Owner", decimals: 9)
        let active = vm.rows.first { $0.id == "Active" }
        let inactive = vm.rows.first { $0.id == "Inactive" }
        XCTAssertEqual(active?.canMoveStake, true)
        XCTAssertEqual(active?.canUnstake, true)
        XCTAssertEqual(active?.canWithdraw, false)
        XCTAssertEqual(inactive?.canMoveStake, false)
        XCTAssertEqual(inactive?.canUnstake, false)
        XCTAssertEqual(inactive?.canWithdraw, true)
    }

    func testEnrichesValidatorNameAndAPYFromMetadata() async {
        let service = FakeStakingService(
            accounts: [account(pubkey: "A", vote: "V1", stake: 1_000_000_000, activationEpoch: 700)],
            validators: [validator(vote: "V1", commission: 5)]
        )
        let vm = SolanaStakeDefiViewModel(
            stakingService: service,
            metadataProvider: FakeMetadataProvider(byVote: [
                "V1": ValidatorMetadata(name: "Vultisig Pool", apyEstimate: Decimal(string: "0.068"))
            ]),
            onInvalidateCaches: {}
        )
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
            stakingService: service,
            metadataProvider: FakeMetadataProvider(byVote: [:]),
            onInvalidateCaches: { invalidated += 1 }
        )
        await vm.refresh(owner: "Owner", decimals: 9)
        await vm.invalidateAndRefresh(owner: "Owner", decimals: 9)
        // Two reads (one per refresh) — stake accounts are never cached — and the
        // cache-invalidation hook fired exactly once on the post-keysign refresh.
        XCTAssertEqual(service.stakeAccountCalls, 2)
        XCTAssertEqual(invalidated, 1)
    }
}
