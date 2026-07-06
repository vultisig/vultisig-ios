//
//  StakingValidator.swift
//  VultisigApp
//
//  Chain-agnostic display projection of a validator row for the shared
//  validator-picker. The per-chain on-chain types (`CosmosValidator`,
//  `SolanaValidator`) keep their full shape for signing/selection; this is the
//  thin value-type the picker card renders, so the card stays one component
//  across Cosmos and Solana.
//

import Foundation

/// Display-only validator row. All strings are pre-formatted for the chain
/// (subtitle already carries the scaled power/stake + ticker; commission already
/// carries the "%"), so the card renders without any chain knowledge.
struct StakingValidator: Hashable {
    /// Primary line — moniker / display name (or a truncated address fallback).
    let name: String
    /// Secondary line — e.g. "200,392 LUNA" voting power or activated stake.
    let subtitle: String
    /// Commission, pre-formatted as "5%".
    let commission: String
    /// Avatar source — either a Keybase identity to resolve, or a ready logo URL,
    /// each with the deterministic monogram fallback.
    let avatar: Avatar

    enum Avatar: Hashable {
        /// Cosmos — resolve the Keybase identity to a profile picture, falling
        /// back to `monogram` while the lookup is in flight or when absent.
        case keybase(identity: String?, monogram: String)
        /// Solana — a ready logo URL (from metadata), falling back to `monogram`.
        case logo(url: URL?, monogram: String)
    }
}
