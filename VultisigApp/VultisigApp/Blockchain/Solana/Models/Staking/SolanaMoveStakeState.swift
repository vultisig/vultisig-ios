//
//  SolanaMoveStakeState.swift
//  VultisigApp
//
//  In-progress state of a guided Solana move-stake (redelegate A → B). Solana
//  has no native redelegate, so a move is a multi-transaction, cross-epoch
//  flow: split the chosen amount → deactivate the moved account → wait ~1 epoch
//  → re-delegate to validator B. There is no on-device journal of where the
//  user is in that flow — instead the PHASE is INFERRED from the on-chain parsed
//  stake account, so it survives app restarts. The destination validator (B),
//  however, only becomes readable on-chain once the re-delegate lands; while the
//  move is still cooling down it is known from local intent alone, so resuming a
//  PENDING move is scoped to the same device/session that started it (a fresh
//  device or reinstall can still observe an already-landed move, just not finish
//  a cooling-down one).
//
//  Inference reads the moved/split account's `activationState` and its current
//  delegation target, gated by `SolanaEpochCooldownGate` for the cooldown:
//
//    activating (to B)  → done? — the account is delegated to B and warming up.
//    active (to B)      → done — fully moved.
//    deactivating       → cooling down; re-delegate not yet possible.
//    inactive (cooled)  → re-delegatable — the "Finish moving to B" CTA.
//    active (to A)      → not started — still earning on the origin validator.
//

import Foundation

/// The badge/CTA-driving phase of one move-stake split account. Pure value
/// type, derived from the parsed stake state + the live epoch, so the badge,
/// the cooldown gate, and the resume CTA all agree on one definition.
enum SolanaMoveStakePhase: String, Equatable, Hashable {
    /// Still delegated to the origin validator (A) — the move hasn't begun, or
    /// this isn't a move-origin account at all.
    case notStarted
    /// Deactivate submitted; the account is cooling down (~1 epoch) and cannot
    /// be re-delegated yet.
    case deactivating
    /// Fully cooled down and undelegated — ready for the "Finish moving" step.
    case reDelegatable
    /// Re-delegated to the destination validator (B) and warming up this epoch.
    case activating
    /// Re-delegated to B and fully active — the move is complete.
    case completed
}

/// Inferred progress of a move-stake for one split/moved account. Carries the
/// phase plus the destination validator so the UI can label the re-delegate CTA
/// and the byte-parity build can target the right validator on resume.
struct SolanaMoveStakeProgress: Equatable, Hashable {
    let stakeAccount: SolanaStakeAccount
    let phase: SolanaMoveStakePhase
    /// The destination validator (B) the move targets. Known while the move is
    /// pending from the local intent; once the account is delegated to B it is
    /// also readable straight off the chain.
    let destinationVotePubkey: String

    /// `true` when the next action is the user-driven "Finish moving to B"
    /// re-delegate — i.e. the cooled-down split account is ready to delegate.
    var canFinishMove: Bool { phase == .reDelegatable }

    /// `true` once the account is delegated to the destination validator
    /// (warming up or active) — the move has effectively landed.
    var isLanded: Bool { phase == .activating || phase == .completed }

    /// Infers the move phase from the on-chain parsed account at `currentEpoch`.
    ///
    /// - Parameters:
    ///   - account: the parsed split/moved stake account.
    ///   - destinationVotePubkey: validator B — the move target.
    ///   - currentEpoch: the live network epoch (drives the cooldown gate).
    static func infer(
        account: SolanaStakeAccount,
        destinationVotePubkey: String,
        currentEpoch: UInt64
    ) -> SolanaMoveStakeProgress {
        let phase = inferPhase(
            account: account,
            destinationVotePubkey: destinationVotePubkey,
            currentEpoch: currentEpoch
        )
        return SolanaMoveStakeProgress(
            stakeAccount: account,
            phase: phase,
            destinationVotePubkey: destinationVotePubkey
        )
    }

    private static func inferPhase(
        account: SolanaStakeAccount,
        destinationVotePubkey: String,
        currentEpoch: UInt64
    ) -> SolanaMoveStakePhase {
        // Already delegated to B — the move has landed. `activationState`
        // distinguishes warming-up from fully active.
        if let delegation = account.delegation, delegation.votePubkey == destinationVotePubkey {
            switch account.activationState(currentEpoch: currentEpoch) {
            case .activating:
                return .activating
            case .active:
                return .completed
            case .deactivating:
                // Re-delegated to B then deactivated again — treat as cooling
                // down rather than a completed move.
                return .deactivating
            case .inactive:
                return .reDelegatable
            }
        }

        // Not delegated to B. An account still actively delegated to the origin
        // validator (no deactivation scheduled) hasn't begun the move.
        if let delegation = account.delegation, delegation.isDeactivationSentinel {
            return .notStarted
        }

        // A deactivation is scheduled (or there is no delegation at all). Use the
        // cooldown gate to tell "still cooling down" from "fully inactive and
        // ready to re-delegate".
        switch SolanaEpochCooldownGate.evaluate(stakeAccount: account, currentEpoch: currentEpoch) {
        case .blocked:
            return .deactivating
        case .available:
            return .reDelegatable
        }
    }
}
