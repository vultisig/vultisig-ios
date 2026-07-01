//
//  SolanaEpochCooldownGateTests.swift
//  VultisigAppTests
//
//  Pins the deactivation-cooldown epoch math: a withdraw unlocks only once the
//  network epoch advances PAST the stake account's deactivationEpoch.
//

@testable import VultisigApp
import XCTest

final class SolanaEpochCooldownGateTests: XCTestCase {

    private func account(deactivationEpoch: UInt64, activationEpoch: UInt64 = 100) -> SolanaStakeAccount {
        SolanaStakeAccount(
            pubkey: "Stake1",
            lamports: 5_000_000_000,
            rentExemptReserve: 2_282_880,
            staker: "Owner",
            withdrawer: "Owner",
            delegation: SolanaStakeAccount.Delegation(
                votePubkey: "Vote1",
                activationEpoch: activationEpoch,
                deactivationEpoch: deactivationEpoch,
                stake: 5_000_000_000
            )
        )
    }

    func testActiveDelegationIsAvailable() {
        // Sentinel deactivation epoch => not deactivating => nothing to gate.
        let acc = account(deactivationEpoch: .max)
        XCTAssertEqual(SolanaEpochCooldownGate.evaluate(stakeAccount: acc, currentEpoch: 993), .available)
    }

    func testUndelegatedAccountIsAvailable() {
        let acc = SolanaStakeAccount(
            pubkey: "Stake1", lamports: 2_282_880, rentExemptReserve: 2_282_880,
            staker: "Owner", withdrawer: "Owner", delegation: nil
        )
        XCTAssertEqual(SolanaEpochCooldownGate.evaluate(stakeAccount: acc, currentEpoch: 993), .available)
    }

    func testBlockedDuringDeactivationEpoch() {
        // Deactivated at epoch 500; current epoch is still 500 -> cooling down.
        let acc = account(deactivationEpoch: 500)
        XCTAssertEqual(
            SolanaEpochCooldownGate.evaluate(stakeAccount: acc, currentEpoch: 500),
            .blocked(unlocksAtEpoch: 501)
        )
    }

    func testBlockedBeforeDeactivationEpoch() {
        // Deactivation scheduled for epoch 600, current epoch 550.
        let acc = account(deactivationEpoch: 600)
        XCTAssertEqual(
            SolanaEpochCooldownGate.evaluate(stakeAccount: acc, currentEpoch: 550),
            .blocked(unlocksAtEpoch: 601)
        )
    }

    func testAvailableAfterDeactivationEpochPasses() {
        // Deactivated at 500; network advanced to 501 -> withdrawable.
        let acc = account(deactivationEpoch: 500)
        XCTAssertEqual(SolanaEpochCooldownGate.evaluate(stakeAccount: acc, currentEpoch: 501), .available)
    }

    func testDeactivatingActivationStateMatchesGate() {
        // The model's activationState and the gate must agree about "deactivating".
        let acc = account(deactivationEpoch: 500)
        XCTAssertEqual(acc.activationState(currentEpoch: 500), .deactivating)
        XCTAssertEqual(acc.activationState(currentEpoch: 501), .inactive)
    }
}
