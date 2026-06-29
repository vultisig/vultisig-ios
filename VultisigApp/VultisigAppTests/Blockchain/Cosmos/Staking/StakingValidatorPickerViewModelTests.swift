//
//  StakingValidatorPickerViewModelTests.swift
//  VultisigAppTests
//
//  Locks the shared validator-picker contract through the Cosmos source —
//  sort-by-voting-power-desc, filter jailed + non-bonded validators out,
//  case-insensitive search across moniker and operator address, exclusion list
//  (used by the redelegate flow to keep the user from redelegating to
//  themselves), and graceful error surfacing on a fetch failure.
//

@testable import VultisigApp
import XCTest

@MainActor
final class StakingValidatorPickerViewModelTests: XCTestCase {

    func testSortAndFilterDropsJailedAndNonBondedAndSortsByVotingPowerDesc() {
        let raw = [
            CosmosValidator(
                operatorAddress: "terravaloper1c",
                moniker: "Charlie",
                commission: 0.05,
                jailed: false,
                status: .bonded,
                votingPower: 100
            ),
            CosmosValidator(
                operatorAddress: "terravaloper1a",
                moniker: "Alice",
                commission: 0.03,
                jailed: false,
                status: .bonded,
                votingPower: 1_000
            ),
            CosmosValidator(
                operatorAddress: "terravaloper1jailed",
                moniker: "Jailed",
                commission: 0.20,
                jailed: true,
                status: .bonded,
                votingPower: 500
            ),
            CosmosValidator(
                operatorAddress: "terravaloper1unbonded",
                moniker: "Unbonded",
                commission: 0.10,
                jailed: false,
                status: .unbonded,
                votingPower: 200
            ),
            CosmosValidator(
                operatorAddress: "terravaloper1b",
                moniker: "Bob",
                commission: 0.04,
                jailed: false,
                status: .bonded,
                votingPower: 250
            )
        ]
        let filtered = CosmosValidator.sortAndFilter(raw)
        XCTAssertEqual(filtered.map(\.moniker), ["Alice", "Bob", "Charlie"])
    }

    func testFilteredValidatorsAppliesCaseInsensitiveSearch() async {
        let vm = StakingValidatorPickerViewModel(
            source: .cosmos(chain: .terra, service: StubService(validators: Self.sampleValidators))
        )
        await vm.load()

        vm.searchText = "all"
        XCTAssertEqual(vm.filteredValidators.map(\.moniker), ["Allnodes"])
    }

    func testFilteredValidatorsMatchesOperatorAddressSubstring() async {
        let vm = StakingValidatorPickerViewModel(
            source: .cosmos(chain: .terra, service: StubService(validators: Self.sampleValidators))
        )
        await vm.load()

        vm.searchText = "VALOPER1A"
        XCTAssertEqual(vm.filteredValidators.map(\.operatorAddress), ["terravaloper1aaa"])
    }

    func testExclusionListHidesSourceValidator() async {
        let vm = StakingValidatorPickerViewModel(
            source: .cosmos(
                chain: .terra,
                excludedValidators: ["terravaloper1aaa"],
                service: StubService(validators: Self.sampleValidators)
            )
        )
        await vm.load()

        XCTAssertFalse(vm.filteredValidators.contains { $0.operatorAddress == "terravaloper1aaa" })
    }

    func testFetchFailureSurfacesErrorAndKeepsEmptyList() async {
        let vm = StakingValidatorPickerViewModel(
            source: .cosmos(chain: .terra, service: ThrowingService())
        )
        await vm.load()

        XCTAssertNotNil(vm.error)
        XCTAssertTrue(vm.filteredValidators.isEmpty)
    }

    // MARK: - Fixtures

    private static let sampleValidators: [CosmosValidator] = [
        CosmosValidator(
            operatorAddress: "terravaloper1aaa",
            moniker: "Allnodes",
            commission: 0.05,
            jailed: false,
            status: .bonded,
            votingPower: 200_392_000_000
        ),
        CosmosValidator(
            operatorAddress: "terravaloper1bbb",
            moniker: "Stakefish",
            commission: 0.10,
            jailed: false,
            status: .bonded,
            votingPower: 150_000_000_000
        )
    ]
}

// MARK: - Stubs

// swiftlint:disable async_without_await unused_parameter
private struct StubService: CosmosStakingServiceProtocol {
    let validators: [CosmosValidator]

    func fetchDelegations(chain: Chain, address: String) async throws -> [CosmosDelegation] { [] }
    func fetchUnbondingDelegations(chain: Chain, address: String) async throws -> [CosmosUnbondingDelegation] { [] }
    func fetchDelegatorRewards(chain: Chain, address: String) async throws -> CosmosDelegatorRewards {
        CosmosDelegatorRewards(rewards: [], total: [])
    }
    func fetchValidators(chain: Chain) async throws -> [CosmosValidator] { validators }
    func fetchRedelegations(chain: Chain, address: String) async throws -> [CosmosRedelegationEntry] { [] }
}

private struct ThrowingService: CosmosStakingServiceProtocol {
    struct StubError: Error {}

    func fetchDelegations(chain: Chain, address: String) async throws -> [CosmosDelegation] { throw StubError() }
    func fetchUnbondingDelegations(chain: Chain, address: String) async throws -> [CosmosUnbondingDelegation] { throw StubError() }
    func fetchDelegatorRewards(chain: Chain, address: String) async throws -> CosmosDelegatorRewards { throw StubError() }
    func fetchValidators(chain: Chain) async throws -> [CosmosValidator] { throw StubError() }
    func fetchRedelegations(chain: Chain, address: String) async throws -> [CosmosRedelegationEntry] { throw StubError() }
}
// swiftlint:enable async_without_await unused_parameter
