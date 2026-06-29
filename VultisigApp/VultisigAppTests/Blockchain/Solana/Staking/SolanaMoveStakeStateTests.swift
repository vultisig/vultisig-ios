//
//  SolanaMoveStakeStateTests.swift
//  VultisigAppTests
//
//  Pins the inferred, resumable move-stake state machine. The phase is derived
//  ENTIRELY from the on-chain parsed stake account + the live epoch (no local
//  journal), so these tests pin every transition across the guided flow:
//  not-started → deactivating → re-delegatable → activating → completed,
//  including the gating by `SolanaEpochCooldownGate` and the resume CTA.
//

@testable import VultisigApp
import XCTest

final class SolanaMoveStakeStateTests: XCTestCase {

    private let originVote = "OriginValidatorVoteA"
    private let destinationVote = "DestinationValidatorVoteB"

    private func account(
        delegation: SolanaStakeAccount.Delegation?,
        lamports: UInt64 = 2_000_000_000,
        rentReserve: UInt64 = 2_282_880
    ) -> SolanaStakeAccount {
        SolanaStakeAccount(
            pubkey: "StakeAccountPubkey",
            lamports: lamports,
            rentExemptReserve: rentReserve,
            staker: "Staker",
            withdrawer: "Withdrawer",
            delegation: delegation
        )
    }

    private func delegation(
        vote: String,
        activationEpoch: UInt64,
        deactivationEpoch: UInt64 = .max,
        stake: UInt64 = 1_999_000_000
    ) -> SolanaStakeAccount.Delegation {
        SolanaStakeAccount.Delegation(
            votePubkey: vote,
            activationEpoch: activationEpoch,
            deactivationEpoch: deactivationEpoch,
            stake: stake
        )
    }

    // MARK: - Not started

    /// Still actively delegated to the origin validator A — the move hasn't begun.
    func testActiveOnOriginIsNotStarted() {
        let acct = account(delegation: delegation(vote: originVote, activationEpoch: 100))
        let progress = SolanaMoveStakeProgress.infer(
            account: acct, destinationVotePubkey: destinationVote, currentEpoch: 110
        )
        XCTAssertEqual(progress.phase, .notStarted)
        XCTAssertFalse(progress.canFinishMove)
        XCTAssertFalse(progress.isLanded)
    }

    // MARK: - Deactivating (cooling down)

    /// Deactivate submitted, current epoch has not passed the deactivation
    /// epoch — cooling down, re-delegate not yet possible.
    func testDeactivatingWhileCoolingDown() {
        let acct = account(
            delegation: delegation(vote: originVote, activationEpoch: 100, deactivationEpoch: 110)
        )
        let progress = SolanaMoveStakeProgress.infer(
            account: acct, destinationVotePubkey: destinationVote, currentEpoch: 110
        )
        XCTAssertEqual(progress.phase, .deactivating)
        XCTAssertFalse(progress.canFinishMove)
    }

    // MARK: - Re-delegatable (cooled down)

    /// Deactivation epoch has passed — fully inactive, ready for the
    /// "Finish moving to B" re-delegate.
    func testCooledDownDelegationIsReDelegatable() {
        let acct = account(
            delegation: delegation(vote: originVote, activationEpoch: 100, deactivationEpoch: 110)
        )
        let progress = SolanaMoveStakeProgress.infer(
            account: acct, destinationVotePubkey: destinationVote, currentEpoch: 111
        )
        XCTAssertEqual(progress.phase, .reDelegatable)
        XCTAssertTrue(progress.canFinishMove)
        XCTAssertFalse(progress.isLanded)
    }

    /// An undelegated account (split landed, never delegated) is re-delegatable.
    func testUndelegatedAccountIsReDelegatable() {
        let acct = account(delegation: nil)
        let progress = SolanaMoveStakeProgress.infer(
            account: acct, destinationVotePubkey: destinationVote, currentEpoch: 200
        )
        XCTAssertEqual(progress.phase, .reDelegatable)
        XCTAssertTrue(progress.canFinishMove)
    }

    // MARK: - Landed on B

    /// Re-delegated to B and warming up this epoch — the move has landed.
    func testActivatingOnDestinationIsActivating() {
        let acct = account(delegation: delegation(vote: destinationVote, activationEpoch: 120))
        let progress = SolanaMoveStakeProgress.infer(
            account: acct, destinationVotePubkey: destinationVote, currentEpoch: 120
        )
        XCTAssertEqual(progress.phase, .activating)
        XCTAssertTrue(progress.isLanded)
        XCTAssertFalse(progress.canFinishMove)
    }

    /// Re-delegated to B in a prior epoch and fully active — move completed.
    func testActiveOnDestinationIsCompleted() {
        let acct = account(delegation: delegation(vote: destinationVote, activationEpoch: 120))
        let progress = SolanaMoveStakeProgress.infer(
            account: acct, destinationVotePubkey: destinationVote, currentEpoch: 130
        )
        XCTAssertEqual(progress.phase, .completed)
        XCTAssertTrue(progress.isLanded)
    }

    // MARK: - Resumability

    /// The phase is a pure function of the on-chain account + epoch, so a second
    /// independent inference (e.g. after an app restart) yields the same phase.
    func testInferenceIsDeterministicAcrossRestarts() {
        let acct = account(
            delegation: delegation(vote: originVote, activationEpoch: 100, deactivationEpoch: 110)
        )
        let first = SolanaMoveStakeProgress.infer(
            account: acct, destinationVotePubkey: destinationVote, currentEpoch: 111
        )
        let second = SolanaMoveStakeProgress.infer(
            account: acct, destinationVotePubkey: destinationVote, currentEpoch: 111
        )
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.phase, .reDelegatable)
    }
}
