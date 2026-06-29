//
//  SolanaValidatorPreflight.swift
//  VultisigApp
//
//  Sanity-checks a Solana validator vote pubkey before the MPC ceremony
//  spends a signing round on a delegate tx the chain would reject
//  post-broadcast. Analog of the Cosmos `ValidatorBech32Preflight` — same
//  posture: validate at build time so an invalid validator throws before any
//  pre-image bytes are produced.
//
//  Two checks:
//
//    1. The vote pubkey is a valid base58 ed25519 Solana address — WalletCore's
//       `AnyAddress(string:coin:)` is the same validator `AddressService` uses
//       for every Solana address, so a malformed or wrong-curve key is rejected
//       here.
//
//    2. (Optional) The vote pubkey is present in a caller-supplied known-vote
//       set (from the cached `getVoteAccounts` read). When the set is empty the
//       check is skipped — the address-shape guard still applies — so the
//       preflight degrades gracefully if the validator list is briefly
//       unavailable rather than blocking a legitimate delegate.
//

import Foundation
import WalletCore

enum SolanaValidatorPreflight {

    enum SolanaValidatorError: Error, LocalizedError, Equatable {
        case empty
        case invalidVotePubkey
        case unknownValidator

        var errorDescription: String? {
            switch self {
            case .empty:
                return "solanaValidatorErrorEmpty".localized
            case .invalidVotePubkey:
                return "solanaValidatorErrorInvalidVotePubkey".localized
            case .unknownValidator:
                return "solanaValidatorErrorUnknownValidator".localized
            }
        }
    }

    /// Validates the vote pubkey's shape and, when `knownVotePubkeys` is
    /// non-empty, its membership in the cached vote-account set.
    ///
    /// - Parameters:
    ///   - votePubkey: the validator vote account the user is delegating to.
    ///   - knownVotePubkeys: vote pubkeys from the cached `getVoteAccounts`
    ///     read. Pass an empty set to skip the membership check (shape-only).
    static func validate(
        _ votePubkey: String,
        knownVotePubkeys: Set<String> = []
    ) throws {
        guard !votePubkey.isEmpty else { throw SolanaValidatorError.empty }

        guard AnyAddress(string: votePubkey, coin: .solana) != nil else {
            throw SolanaValidatorError.invalidVotePubkey
        }

        guard knownVotePubkeys.isEmpty || knownVotePubkeys.contains(votePubkey) else {
            throw SolanaValidatorError.unknownValidator
        }
    }
}
