//
//  CatalogToken.swift
//  VultisigApp
//
//  A candidate token the app-wide `TokenCatalogRepository` can offer, carrying
//  the underlying `CoinMeta` plus the provenance the UI / discovery gate on.
//  This is the wrapper that keeps trust OFF `CoinMeta` (see `TokenVerification`):
//  dedup / identity stay on `meta.uniqueId`, while `verification` + `sourceKind`
//  travel alongside for verification-to-surface and badging.
//
//  A `CatalogToken` is a *candidate* — appearing here does not enable it. The
//  enabled set stays `vault.coins` (SwiftData); nothing enters it without an
//  explicit user action or a trusted-discovery path.
//

import Foundation

struct CatalogToken: Equatable, Sendable, Codable {
    let meta: CoinMeta
    let verification: TokenVerification
    /// Discriminator of the provider that offered this token (`kind`), for
    /// logging / debugging. Dedup is by `meta.uniqueId`, so colliding
    /// `sourceKind`s don't affect merge behaviour.
    let sourceKind: String

    init(meta: CoinMeta, verification: TokenVerification, sourceKind: String) {
        self.meta = meta
        self.verification = verification
        self.sourceKind = sourceKind
    }

    /// App-wide dedup identity — the same key every dynamic-source merge uses.
    var uniqueId: String { meta.uniqueId }

    /// Whether this candidate may auto-surface (curated / verified). Mirror of
    /// `verification.autoSurfaces`, exposed here so consumers filter without
    /// reaching through to the enum.
    var autoSurfaces: Bool { verification.autoSurfaces }
}
