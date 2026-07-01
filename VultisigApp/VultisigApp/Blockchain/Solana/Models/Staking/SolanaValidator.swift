//
//  SolanaValidator.swift
//  VultisigApp
//
//  A validator row from `getVoteAccounts` plus an optional metadata enrichment
//  struct (name / logo / APY / score) populated by a later PR. The base row is
//  decoded straight off the RPC; `ValidatorMetadata` starts empty so the
//  read layer can ship before the enrichment source is wired.
//

import Foundation

struct SolanaValidator: Codable, Hashable, Identifiable {
    /// Vote account address — the delegation target a stake account points at.
    let votePubkey: String
    /// The validator's identity (node) pubkey.
    let nodePubkey: String
    /// Total active stake delegated to this validator, in lamports.
    let activatedStake: UInt64
    /// Commission percentage (0–100) the validator takes from rewards.
    let commission: Int
    /// Whether this vote account has voted in the current epoch.
    let epochVoteAccount: Bool
    /// `true` when the validator is in the delinquent set (not voting). Carried
    /// from which `getVoteAccounts` bucket the row came from, not the wire.
    let isDelinquent: Bool
    /// Enrichment populated in a later PR — name, logo, APY estimate, score.
    var metadata: ValidatorMetadata

    var id: String { votePubkey }

    init(
        votePubkey: String,
        nodePubkey: String,
        activatedStake: UInt64,
        commission: Int,
        epochVoteAccount: Bool,
        isDelinquent: Bool,
        metadata: ValidatorMetadata = ValidatorMetadata()
    ) {
        self.votePubkey = votePubkey
        self.nodePubkey = nodePubkey
        self.activatedStake = activatedStake
        self.commission = commission
        self.epochVoteAccount = epochVoteAccount
        self.isDelinquent = isDelinquent
        self.metadata = metadata
    }

    /// Builds from a decoded `getVoteAccounts` row, tagging it with the
    /// delinquent flag derived from its bucket (`current` vs `delinquent`).
    init(voteAccount: SolanaVoteAccount, isDelinquent: Bool) {
        self.init(
            votePubkey: voteAccount.votePubkey,
            nodePubkey: voteAccount.nodePubkey,
            activatedStake: voteAccount.activatedStake,
            commission: voteAccount.commission,
            epochVoteAccount: voteAccount.epochVoteAccount,
            isDelinquent: isDelinquent
        )
    }
}

// MARK: - Display fallbacks

extension SolanaValidator {
    /// Name to show in the picker: the enriched metadata name when present,
    /// otherwise a truncated vote pubkey (`9gAN…7mq`). Keeps the display layer
    /// independent of whether the metadata provider returned anything.
    var displayName: String {
        if let name = metadata.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        return Self.truncatedPubkey(votePubkey)
    }

    /// The validator logo URL, or `nil` when no metadata source supplied one —
    /// the display layer then renders a deterministic placeholder.
    var logoURL: URL? {
        guard let raw = metadata.logoURL?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        return URL(string: raw)
    }

    /// `prefix…suffix` form of a base58 pubkey for compact display. Returns the
    /// input unchanged when it is too short to truncate meaningfully.
    static func truncatedPubkey(_ pubkey: String, prefix: Int = 4, suffix: Int = 4) -> String {
        guard pubkey.count > prefix + suffix + 1 else { return pubkey }
        return "\(pubkey.prefix(prefix))…\(pubkey.suffix(suffix))"
    }
}

/// Off-chain enrichment for a validator. All optional — populated by a later
/// PR from a metadata source; the base read layer leaves it empty.
struct ValidatorMetadata: Codable, Hashable {
    var name: String?
    var logoURL: String?
    /// Estimated APY as a fraction (e.g. 0.067 for 6.7%).
    var apyEstimate: Decimal?
    /// A 0–100 quality score from the metadata source.
    var score: Int?

    init(name: String? = nil, logoURL: String? = nil, apyEstimate: Decimal? = nil, score: Int? = nil) {
        self.name = name
        self.logoURL = logoURL
        self.apyEstimate = apyEstimate
        self.score = score
    }
}

// MARK: - getVoteAccounts wire types

/// A single row of the `getVoteAccounts` `current` / `delinquent` arrays.
struct SolanaVoteAccount: Decodable {
    let votePubkey: String
    let nodePubkey: String
    let activatedStake: UInt64
    let commission: Int
    let epochVoteAccount: Bool
}

struct SolanaVoteAccountsResult: Decodable {
    let current: [SolanaVoteAccount]
    let delinquent: [SolanaVoteAccount]
}

struct SolanaGetVoteAccountsResponse: Decodable {
    let result: SolanaVoteAccountsResult
}
