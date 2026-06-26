//
//  ValidatorMetadataProvider.swift
//  VultisigApp
//
//  Swappable seam for off-chain validator enrichment (name / logo / APY /
//  score). The core stake/commission/activation data comes from the on-chain
//  `getVoteAccounts` read; this protocol only supplies display metadata, which
//  is the part most likely to change source (Stakewiz today, validators.app or
//  an in-house endpoint tomorrow). Keeping it behind a protocol lets the picker
//  and view models stay independent of any single provider.
//
//  Contract: implementations MUST NOT throw on a provider outage. A failed or
//  rate-limited source returns a partial or empty map so callers degrade
//  gracefully — falling back to a truncated vote pubkey and the on-chain
//  commission, with no logo, never a crash.
//

import Foundation

/// Resolves off-chain `ValidatorMetadata` for a set of vote accounts.
protocol ValidatorMetadataProvider: Sendable {
    /// Returns metadata keyed by vote pubkey for the requested validators.
    ///
    /// The returned map may be empty or cover only a subset of the input — a
    /// validator absent from the map simply has no enrichment available and the
    /// caller falls back to on-chain data. This call never throws.
    func metadata(forVotePubkeys votePubkeys: [String]) async -> [String: ValidatorMetadata]
}
