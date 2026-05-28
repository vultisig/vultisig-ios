//
//  CosmosStakeDefiViewModelTests.swift
//  VultisigAppTests
//
//  Tests the position-row pipeline — APY computation via the resolver,
//  baseline fallback when the resolver returns nil, validator identity
//  propagation, per-validator pending-unbonding lookup, and the churned
//  out / locked-when-unbonding gating that the view layer reads to
//  disable Undelegate + Redelegate.
//

@testable import VultisigApp
import Foundation
import XCTest

@MainActor
final class CosmosStakeDefiViewModelTests: XCTestCase {

    func testRefreshUsesResolverChainAPYWhenAvailable() async {
        let validator = Self.validator(address: "terravaloper1abc", commission: 0.05, identity: "kb1")
        let chainData = CosmosChainApyData(
            inflation: Decimal(string: "0.07")!,
            bondedRatio: Decimal(string: "0.5")!,
            communityTax: Decimal(string: "0.02")!
        )
        let vm = CosmosStakeDefiViewModel(
            chain: .terra,
            stakingService: StubStakingService(
                delegations: [Self.delegation(validatorAddress: validator.operatorAddress, amount: "1000000")],
                validators: [validator]
            ),
            apyResolver: StubAPYResolver(chainData: chainData)
        )
        await vm.refresh(address: "terra1abc", decimals: 6)
        XCTAssertEqual(vm.positions.count, 1)
        // expected = 0.98 × 0.14 × 0.95 = 0.13034
        let apy = vm.positions[0].apyPercent
        XCTAssertNotNil(apy)
        XCTAssertEqual((apy as NSDecimalNumber?)?.doubleValue ?? 0, 0.13034, accuracy: 0.00001)
        XCTAssertEqual(vm.positions[0].validatorIdentity, "kb1")
    }

    func testRefreshFallsBackToBaselineWhenChainAPYResolutionFails() async {
        let validator = Self.validator(address: "terravaloper1abc", commission: 0.10, identity: nil)
        let vm = CosmosStakeDefiViewModel(
            chain: .terra,
            stakingService: StubStakingService(
                delegations: [Self.delegation(validatorAddress: validator.operatorAddress, amount: "1000000")],
                validators: [validator]
            ),
            apyResolver: StubAPYResolver(chainData: nil)
        )
        await vm.refresh(address: "terra1abc", decimals: 6)
        // baseline = 0.125 × (1 - 0.10) = 0.1125
        let apy = vm.positions[0].apyPercent
        XCTAssertNotNil(apy)
        XCTAssertEqual((apy as NSDecimalNumber?)?.doubleValue ?? 0, 0.1125, accuracy: 0.00001)
    }

    func testRefreshUsesNilAPYForTerraClassicWhenResolverAndBaselineMiss() async {
        let validator = Self.validator(address: "terravaloper1abc", commission: 0.05, identity: nil)
        let vm = CosmosStakeDefiViewModel(
            chain: .terraClassic,
            stakingService: StubStakingService(
                delegations: [Self.delegation(validatorAddress: validator.operatorAddress, amount: "1000000")],
                validators: [validator]
            ),
            apyResolver: StubAPYResolver(chainData: nil)
        )
        await vm.refresh(address: "terra1abc", decimals: 6)
        XCTAssertNil(vm.positions[0].apyPercent)
    }

    func testRefreshPopulatesPendingUnbondingUnlockDateFromMatchingValidator() async {
        let validator = Self.validator(address: "terravaloper1abc", commission: 0.05)
        let future = Date(timeIntervalSinceNow: 86_400 * 21)
        let later = Date(timeIntervalSinceNow: 86_400 * 30)
        let unbonding = CosmosUnbondingDelegation(
            validatorAddress: validator.operatorAddress,
            entries: [
                CosmosUnbondingEntry(creationHeight: 1, completionTime: later, initialBalance: 0, balance: 0),
                CosmosUnbondingEntry(creationHeight: 2, completionTime: future, initialBalance: 0, balance: 0)
            ]
        )
        let vm = CosmosStakeDefiViewModel(
            chain: .terra,
            stakingService: StubStakingService(
                delegations: [Self.delegation(validatorAddress: validator.operatorAddress, amount: "1000000")],
                validators: [validator],
                unbondings: [unbonding]
            ),
            apyResolver: StubAPYResolver(chainData: nil)
        )
        await vm.refresh(address: "terra1abc", decimals: 6)
        let row = vm.positions[0]
        XCTAssertNotNil(row.pendingUnbondingUnlockDate)
        XCTAssertEqual(row.pendingUnbondingUnlockDate, future)
    }

    func testRefreshDoesNotSetUnlockDateForOtherValidator() async {
        let staked = Self.validator(address: "terravaloper1abc", commission: 0.05)
        let unbondedOther = CosmosUnbondingDelegation(
            validatorAddress: "terravaloper1other",
            entries: [
                CosmosUnbondingEntry(
                    creationHeight: 1,
                    completionTime: Date(timeIntervalSinceNow: 86_400),
                    initialBalance: 0,
                    balance: 0
                )
            ]
        )
        let vm = CosmosStakeDefiViewModel(
            chain: .terra,
            stakingService: StubStakingService(
                delegations: [Self.delegation(validatorAddress: staked.operatorAddress, amount: "1000000")],
                validators: [staked],
                unbondings: [unbondedOther]
            ),
            apyResolver: StubAPYResolver(chainData: nil)
        )
        await vm.refresh(address: "terra1abc", decimals: 6)
        XCTAssertNil(vm.positions[0].pendingUnbondingUnlockDate)
    }

    func testRefreshIgnoresAlreadyExpiredUnbondings() async {
        let validator = Self.validator(address: "terravaloper1abc", commission: 0.05)
        let expired = CosmosUnbondingDelegation(
            validatorAddress: validator.operatorAddress,
            entries: [
                CosmosUnbondingEntry(
                    creationHeight: 1,
                    completionTime: Date(timeIntervalSinceNow: -86_400),
                    initialBalance: 0,
                    balance: 0
                )
            ]
        )
        let vm = CosmosStakeDefiViewModel(
            chain: .terra,
            stakingService: StubStakingService(
                delegations: [Self.delegation(validatorAddress: validator.operatorAddress, amount: "1000000")],
                validators: [validator],
                unbondings: [expired]
            ),
            apyResolver: StubAPYResolver(chainData: nil)
        )
        await vm.refresh(address: "terra1abc", decimals: 6)
        XCTAssertNil(vm.positions[0].pendingUnbondingUnlockDate)
    }

    // MARK: - Fixtures

    private static func validator(
        address: String,
        commission: Decimal,
        identity: String? = nil
    ) -> CosmosValidator {
        CosmosValidator(
            operatorAddress: address,
            moniker: "Validator",
            commission: commission,
            jailed: false,
            status: .bonded,
            votingPower: 100,
            identity: identity
        )
    }

    private static func delegation(validatorAddress: String, amount: String) -> CosmosDelegation {
        CosmosDelegation(
            validatorAddress: validatorAddress,
            balance: CosmosStakingCoin(denom: "uluna", amount: amount),
            shares: "\(amount).000000000000000000"
        )
    }
}

// MARK: - Test doubles

private struct StubStakingService: CosmosStakingServiceProtocol {
    let delegations: [CosmosDelegation]
    let validators: [CosmosValidator]
    let unbondings: [CosmosUnbondingDelegation]
    let rewards: CosmosDelegatorRewards

    init(
        delegations: [CosmosDelegation] = [],
        validators: [CosmosValidator] = [],
        unbondings: [CosmosUnbondingDelegation] = [],
        rewards: CosmosDelegatorRewards = CosmosDelegatorRewards(rewards: [], total: [])
    ) {
        self.delegations = delegations
        self.validators = validators
        self.unbondings = unbondings
        self.rewards = rewards
    }

    func fetchDelegations(chain _: Chain, address _: String) async throws -> [CosmosDelegation] { delegations }
    func fetchUnbondingDelegations(chain _: Chain, address _: String) async throws -> [CosmosUnbondingDelegation] { unbondings }
    func fetchDelegatorRewards(chain _: Chain, address _: String) async throws -> CosmosDelegatorRewards { rewards }
    func fetchValidators(chain _: Chain) async throws -> [CosmosValidator] { validators }
    func fetchRedelegations(chain _: Chain, address _: String) async throws -> [CosmosRedelegationEntry] { [] }
}

private struct StubAPYResolver: CosmosStakingAPYResolverProtocol {
    let chainData: CosmosChainApyData?

    func chainApy(chain _: Chain, stakingDenom _: String) async -> CosmosChainApyData? { chainData }

    func baselineFallback(chain: Chain) -> Decimal? {
        switch chain {
        case .terra: return Decimal(string: "0.125")
        default: return nil
        }
    }
}
