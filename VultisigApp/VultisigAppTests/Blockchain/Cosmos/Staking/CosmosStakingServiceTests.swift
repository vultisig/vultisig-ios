//
//  CosmosStakingServiceTests.swift
//  VultisigAppTests
//
//  DTO parse coverage for the Cosmos x/staking + x/distribution LCD
//  reader. Each test exercises a single endpoint via a fixture JSON copy
//  of the on-the-wire shape; the SDK / agent app produce the same shapes
//  so the parsing tests double as a wire-format contract.
//
//  Fixtures live in `VultisigAppTests/Blockchain/Cosmos/Staking/
//  CosmosStakingFixtures/` (a folder reference so the JSONs land under
//  `CosmosStakingFixtures/*.json` in the bundle rather than flattening
//  to the root — the root is reserved for `ChainHelperTests`).
//

@testable import VultisigApp
import XCTest

final class CosmosStakingServiceTests: XCTestCase {

    // MARK: - Delegations

    func testDelegationsResponseParsesAllEntriesAndPreservesOrder() throws {
        let response: CosmosDelegationResponse = try loadFixture("delegations")
        let delegations = response.toDelegations()
        XCTAssertEqual(delegations.count, 2)
        XCTAssertEqual(delegations[0].validatorAddress, "terravaloper1aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
        XCTAssertEqual(delegations[0].balance, CosmosStakingCoin(denom: "uluna", amount: "1000000"))
        XCTAssertEqual(delegations[0].shares, "1000000.000000000000000000")
        XCTAssertEqual(delegations[1].validatorAddress, "terravaloper1bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")
        XCTAssertEqual(delegations[1].balance.amount, "500000")
    }

    // MARK: - Unbonding delegations

    func testUnbondingDelegationsParseAllEntriesAndDecodeDates() throws {
        let response: CosmosUnbondingDelegationResponse = try loadFixture("unbonding-delegations")
        let unbonding = response.toUnbondingDelegations()
        XCTAssertEqual(unbonding.count, 1)
        let entries = unbonding[0].entries
        XCTAssertEqual(entries.count, 2)

        // First entry: RFC3339 with fractional seconds — the SDK ships
        // this shape from on-chain payouts that aren't aligned to whole-
        // second boundaries.
        XCTAssertEqual(entries[0].creationHeight, 12_345_678)
        XCTAssertEqual(entries[0].initialBalance, Decimal(string: "100000"))
        XCTAssertEqual(entries[0].balance, Decimal(string: "100000"))
        XCTAssertNotNil(entries[0].completionTime)

        // Second entry: whole-second completion time — both formats must
        // parse without the fractional component making it mandatory.
        XCTAssertEqual(entries[1].creationHeight, 12_345_700)
        XCTAssertNotNil(entries[1].completionTime)
        XCTAssertGreaterThan(entries[1].completionTime, entries[0].completionTime)
    }

    // MARK: - Rewards

    func testDelegatorRewardsParsesMultiValidatorRewardsAndTotal() throws {
        let response: CosmosDelegatorRewardsResponse = try loadFixture("rewards")
        let rewards = response.toRewards()
        XCTAssertEqual(rewards.rewards.count, 2)
        XCTAssertEqual(rewards.total.count, 1)
        XCTAssertEqual(rewards.total[0], CosmosStakingCoin(denom: "uluna", amount: "178456.789000000000000000"))
    }

    func testDelegatorRewardsFallsBackToEmptyOnNullPayload() throws {
        // `rewards: null` and `total: null` arrive from some LCD firmwares
        // when the delegator has never accrued. The SDK falls back to []
        // at lcdQueries.ts:198-202 — iOS must do the same.
        let response: CosmosDelegatorRewardsResponse = try loadFixture("rewards-empty")
        let rewards = response.toRewards()
        XCTAssertTrue(rewards.rewards.isEmpty)
        XCTAssertTrue(rewards.total.isEmpty)
    }

    // MARK: - Validators

    func testValidatorListMapsStatusFlags() throws {
        let response: CosmosValidatorListResponse = try loadFixture("validators")
        let validators = response.toValidators()
        XCTAssertEqual(validators.count, 3)

        XCTAssertEqual(validators[0].moniker, "Validator A")
        XCTAssertEqual(validators[0].status, .bonded)
        XCTAssertFalse(validators[0].jailed)
        XCTAssertEqual(validators[0].commission, Decimal(string: "0.050000000000000000"))
        XCTAssertEqual(validators[0].votingPower, Decimal(string: "50000000000000"))

        XCTAssertEqual(validators[1].moniker, "Validator B (Jailed)")
        XCTAssertTrue(validators[1].jailed)
        XCTAssertEqual(validators[1].status, .bonded)

        XCTAssertEqual(validators[2].status, .unbonded)
    }

    func testValidatorJailedDefaultsFalseWhenMissing() throws {
        // The `jailed` field is missing from the unbonded validator entry
        // (`Validator C`). Cosmos LCDs sometimes omit `false` booleans;
        // the wire DTO must default to `false` rather than failing decode.
        let response: CosmosValidatorListResponse = try loadFixture("validators")
        let unbonded = response.toValidators().first { $0.moniker.contains("Unbonded") }
        XCTAssertFalse(unbonded?.jailed ?? true)
    }

    // MARK: - Redelegations

    func testRedelegationsResponseFlattensAllEntriesAndDecodesDates() throws {
        let response: CosmosRedelegationResponse = try loadFixture("redelegations")
        let entries = response.toRedelegations()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].srcValidator, "terravaloper1srcsrcsrcsrcsrcsrcsrcsrcsrcsrcsrcsrcs")
        XCTAssertEqual(entries[0].dstValidator, "terravaloper1dstdstdstdstdstdstdstdstdstdstdstdsts")
        // Whole-second completion time decodes via the same fractional-
        // seconds-tolerant ISO8601 formatter.
        XCTAssertNotNil(entries[0].completionTime)
    }

    // MARK: - Bundle loader

    private func loadFixture<T: Decodable>(_ name: String) throws -> T {
        let bundle = Bundle(for: type(of: self))
        guard let url = bundle.url(
            forResource: name,
            withExtension: "json",
            subdirectory: "CosmosStakingFixtures"
        ) else {
            throw NSError(
                domain: "CosmosStakingServiceTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Missing fixture CosmosStakingFixtures/\(name).json"]
            )
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(T.self, from: data)
    }
}
