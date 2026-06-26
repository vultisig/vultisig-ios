//
//  SolanaStakingPayloadTests.swift
//  VultisigAppTests
//
//  Pins the staking-payload factories + Codable/Hashable round-trip.
//

@testable import VultisigApp
import XCTest

final class SolanaStakingPayloadTests: XCTestCase {

    func testDelegateFactory() {
        let payload = SolanaStakingPayload.delegate(votePubkey: "Vote1", lamports: 2_000_000_000)
        XCTAssertEqual(payload.opType, .delegate)
        XCTAssertEqual(payload.votePubkey, "Vote1")
        XCTAssertEqual(payload.lamports, 2_000_000_000)
        XCTAssertNil(payload.stakeAccount)
        XCTAssertNil(payload.destinationStakeAccount)
    }

    func testUnstakeFactoryCarriesNoAmount() {
        let payload = SolanaStakingPayload.unstake(stakeAccount: "Stake1")
        XCTAssertEqual(payload.opType, .unstake)
        XCTAssertEqual(payload.stakeAccount, "Stake1")
        XCTAssertNil(payload.lamports)
        XCTAssertNil(payload.votePubkey)
    }

    func testWithdrawFactory() {
        let payload = SolanaStakingPayload.withdraw(stakeAccount: "Stake1", lamports: 5)
        XCTAssertEqual(payload.opType, .withdraw)
        XCTAssertEqual(payload.stakeAccount, "Stake1")
        XCTAssertEqual(payload.lamports, 5)
    }

    func testMoveStakeStepFactory() {
        let payload = SolanaStakingPayload.moveStakeStep(
            stakeAccount: "Src", destinationStakeAccount: "Dst", votePubkey: "Vote1", lamports: 7
        )
        XCTAssertEqual(payload.opType, .moveStakeStep)
        XCTAssertEqual(payload.stakeAccount, "Src")
        XCTAssertEqual(payload.destinationStakeAccount, "Dst")
        XCTAssertEqual(payload.votePubkey, "Vote1")
        XCTAssertEqual(payload.lamports, 7)
    }

    func testCodableRoundTrip() throws {
        let original = SolanaStakingPayload.moveStakeStep(
            stakeAccount: "Src", destinationStakeAccount: "Dst", votePubkey: "Vote1", lamports: 7
        )
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SolanaStakingPayload.self, from: encoded)
        XCTAssertEqual(decoded, original)
    }

    func testHashableDistinguishesOps() {
        let delegate = SolanaStakingPayload.delegate(votePubkey: "Vote1", lamports: 1)
        let withdraw = SolanaStakingPayload.withdraw(stakeAccount: "Vote1", lamports: 1)
        XCTAssertNotEqual(delegate, withdraw)
        XCTAssertNotEqual(Set([delegate, withdraw]).count, 1)
    }
}
