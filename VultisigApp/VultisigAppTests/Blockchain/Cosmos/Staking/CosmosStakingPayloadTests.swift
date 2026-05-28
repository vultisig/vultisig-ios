//
//  CosmosStakingPayloadTests.swift
//  VultisigAppTests
//
//  Locks the `CosmosStakingPayload` factory contract so the per-flow
//  builders can rely on the field-discrimination invariants without
//  re-validating per call site.
//

@testable import VultisigApp
import XCTest

final class CosmosStakingPayloadTests: XCTestCase {

    func testDelegateFactoryPopulatesOnlyValidatorAndAmount() {
        let payload = CosmosStakingPayload.delegate(
            validator: "terravaloper1abc",
            denom: "uluna",
            amount: "1000000"
        )
        XCTAssertEqual(payload.opType, .delegate)
        XCTAssertEqual(payload.validatorAddress, "terravaloper1abc")
        XCTAssertEqual(payload.amount, "1000000")
        XCTAssertEqual(payload.denom, "uluna")
        XCTAssertNil(payload.validatorSrcAddress)
        XCTAssertNil(payload.validatorDstAddress)
        XCTAssertNil(payload.validators)
    }

    func testUndelegateFactoryReusesValidatorField() {
        let payload = CosmosStakingPayload.undelegate(
            validator: "terravaloper1abc",
            denom: "uluna",
            amount: "500000"
        )
        XCTAssertEqual(payload.opType, .undelegate)
        XCTAssertEqual(payload.validatorAddress, "terravaloper1abc")
        XCTAssertEqual(payload.amount, "500000")
        XCTAssertNil(payload.validatorSrcAddress)
        XCTAssertNil(payload.validatorDstAddress)
    }

    func testRedelegateFactoryPopulatesSrcAndDstNotValidator() {
        let payload = CosmosStakingPayload.redelegate(
            src: "terravaloper1src",
            dst: "terravaloper1dst",
            denom: "uluna",
            amount: "250000"
        )
        XCTAssertEqual(payload.opType, .redelegate)
        XCTAssertEqual(payload.validatorSrcAddress, "terravaloper1src")
        XCTAssertEqual(payload.validatorDstAddress, "terravaloper1dst")
        XCTAssertEqual(payload.amount, "250000")
        XCTAssertNil(payload.validatorAddress)
    }

    func testWithdrawRewardsFactoryCarriesValidatorListNoAmount() {
        let payload = CosmosStakingPayload.withdrawRewards(
            validators: ["terravaloper1abc", "terravaloper1def"],
            denom: "uluna"
        )
        XCTAssertEqual(payload.opType, .withdrawRewards)
        XCTAssertEqual(payload.validators, ["terravaloper1abc", "terravaloper1def"])
        XCTAssertNil(payload.amount)
        XCTAssertNil(payload.validatorAddress)
    }

    func testCodableRoundTripPreservesAllFields() throws {
        let payload = CosmosStakingPayload.redelegate(
            src: "terravaloper1src",
            dst: "terravaloper1dst",
            denom: "uluna",
            amount: "250000"
        )
        let encoded = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(CosmosStakingPayload.self, from: encoded)
        XCTAssertEqual(decoded, payload)
    }
}
