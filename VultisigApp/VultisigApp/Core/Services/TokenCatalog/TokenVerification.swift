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
//  Precedence, most authoritative first: `.curated` (bundled `TokensStore`),
//  then `.scam` (positively identified as malicious), then `.verified(source:)`
//  (a source-side allowlist — 1inch's `/tokens` whitelist, Jupiter's
//  `?query=verified`), then `.unverified` (long-tail / source-flagged /
//  unknown).
//  Only `.curated`/`.verified` auto-surface in search + discovery; `.unverified`
//  stay reachable but must be opted into and are badged (MetaMask/Rabby model).
//

import Foundation

/// TRUST BOUNDARY — `Codable` here exists ONLY to persist the app's own
/// last-good catalog snapshot (a cache we write from values our providers
/// already computed). A `TokenVerification` MUST NOT be decoded straight from a
/// third-party source payload: that would let a remote list self-assert
/// `.verified` and auto-surface. Providers assign verification in code from a
/// validated signal (1inch's curated `/tokens` whitelist minus its `RISK:*`-tagged
/// entries, Jupiter's `?query=verified` list, curated bundling) — never from a
/// decoded field. The disk snapshot caps
/// verification at `.verified` on load (never `.curated`) rather than fully
/// trusting the persisted value (see `TokenCatalogDiskCache`).
enum TokenVerification: Equatable, Hashable, Sendable, Codable {
    /// Bundled, hand-curated `TokensStore` entry — the offline trust anchor.
    case curated
    /// Vouched for by a named source-side allowlist (e.g. "1inch", "Jupiter").
    case verified(source: String)
    /// Long-tail / unknown provenance — must not auto-surface.
    case unverified
    /// Positively identified as malicious — typically a token impersonating a
    /// verified one's symbol or name from a different contract address, or one
    /// an indexer flagged. Distinct from `.unverified`: that is an absence of
    /// evidence, this is evidence.
    case scam

    /// Merge rank: higher wins when the same `uniqueId` is seen with different
    /// verifications across providers. Ranks authority, not trust — `.scam`
    /// outranks `.verified` because a positive identification says more than a
    /// source-side allowlist, while `.curated` outranks `.scam` because the
    /// bundled list is in-code and cannot be tampered with.
    var rank: Int {
        switch self {
        case .curated: return 3
        case .scam: return 2
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
        case .unverified, .scam: return false
        }
    }

    /// Human-facing source label, when there is one (`.verified` only).
    var sourceLabel: String? {
        switch self {
        case .verified(let source): return source
        case .curated, .unverified, .scam: return nil
        }
    }

    /// The stronger of two verifications by `rank`; ties keep `lhs`. Used by the
    /// repository merge so a token vouched for by any provider keeps its
    /// strongest signal even when a lower-precedence provider supplies the
    /// winning `CoinMeta` (curated logo / priceProviderId).
    ///
    /// A `.scam` finding survives a merge with a provider that merely does not
    /// recognise the address — ignorance is not evidence against a positive
    /// identification — but never displaces `.curated`, which no remote source
    /// or persisted snapshot may override. Both fall out of `rank`.
    static func stronger(_ lhs: TokenVerification, _ rhs: TokenVerification) -> TokenVerification {
        rhs.rank > lhs.rank ? rhs : lhs
    }

    /// Verification a value loaded from untrusted persistence (the disk snapshot)
    /// may claim. `.curated` is reserved for the in-memory bundled provider and
    /// wins dedup precedence, so a persisted/tampered token is capped at
    /// `.verified` — it can never masquerade as curated. `.verified`/`.unverified`
    /// are preserved so a provider's last-good verified list still surfaces
    /// offline / during a transient outage (rather than being filtered out and
    /// letting the outer cache overwrite a complete list with a bundled-only one).
    /// `.scam` is preserved too: the worst a tampered one can do is hide a token
    /// from search, which is the fail-closed direction, and it cannot reach
    /// `.curated` entries because those outrank it.
    var cappedForUntrustedPersistence: TokenVerification {
        switch self {
        case .curated: return .verified(source: "cached")
        case .verified, .unverified, .scam: return self
        }
    }
}
