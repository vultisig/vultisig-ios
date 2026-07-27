//
//  TokenVerification.swift
//  VultisigApp
//
//  Trust signal a token catalog source attaches to a candidate token. Kept
//  OFF `CoinMeta` on purpose: `CoinMeta.uniqueId`/`==`/`hash` are the app-wide
//  dedup identity and every dynamic-source merge relies on them, so widening
//  that identity with a trust field would silently change dedup behaviour.
//  Trust instead rides on the `CatalogToken` wrapper the repository emits.
//
//  Precedence: `.curated` (bundled `TokensStore`) is the strongest signal,
//  then `.verified(source:)` (a source-side allowlist — 1inch CoinGecko,
//  Jupiter's `?query=verified`), then `.unverified` (long-tail / unknown).
//  Only `.curated`/`.verified` auto-surface in search + discovery; `.unverified`
//  stay reachable but must be opted into and are badged (MetaMask/Rabby model).
//

import Foundation

/// TRUST BOUNDARY — `Codable` here exists ONLY to persist the app's own
/// last-good catalog snapshot (a cache we write from values our providers
/// already computed). A `TokenVerification` MUST NOT be decoded straight from a
/// third-party source payload: that would let a remote list self-assert
/// `.verified` and auto-surface. Providers assign verification in code from a
/// validated signal (1inch `isCoinGeckoVerified`, Jupiter's `?query=verified`
/// list, curated bundling) — never from a decoded field. The disk snapshot
/// floors verification to `.unverified` on load rather than trusting the
/// persisted value (see `TokenCatalogDiskCache`).
enum TokenVerification: Equatable, Hashable, Sendable, Codable {
    /// Bundled, hand-curated `TokensStore` entry — the offline trust anchor.
    case curated
    /// Vouched for by a named source-side allowlist (e.g. "CoinGecko", "Jupiter").
    case verified(source: String)
    /// Long-tail / unknown provenance — must not auto-surface.
    case unverified

    /// Merge rank: higher wins when the same `uniqueId` is seen with different
    /// verifications across providers (the strongest signal is kept).
    var rank: Int {
        switch self {
        case .curated: return 2
        case .verified: return 1
        case .unverified: return 0
        }
    }

    /// Whether a token with this verification may appear in search / discovery
    /// without an explicit opt-in. Curated + verified auto-surface; unverified
    /// do not (defense against lookalike / scam / airdrop-dust tokens).
    var autoSurfaces: Bool {
        switch self {
        case .curated, .verified: return true
        case .unverified: return false
        }
    }

    /// Human-facing source label, when there is one (`.verified` only).
    var sourceLabel: String? {
        switch self {
        case .verified(let source): return source
        case .curated, .unverified: return nil
        }
    }

    /// The stronger of two verifications by `rank`; ties keep `lhs`. Used by the
    /// repository merge so a token vouched for by any provider keeps its
    /// strongest signal even when a lower-precedence provider supplies the
    /// winning `CoinMeta` (curated logo / priceProviderId).
    static func stronger(_ lhs: TokenVerification, _ rhs: TokenVerification) -> TokenVerification {
        rhs.rank > lhs.rank ? rhs : lhs
    }
}
