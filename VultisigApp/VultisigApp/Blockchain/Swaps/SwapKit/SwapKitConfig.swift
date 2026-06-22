//
//  SwapKitConfig.swift
//  VultisigApp
//
//  Configuration constants for the SwapKit aggregator integration. iOS does
//  NOT call `api.swapkit.dev` directly — requests are routed through a
//  Vultisig backend proxy at `https://api.vultisig.com/swapkit/` which
//  attaches the partner API key server-side. Same pattern as the existing
//  1inch proxy (`api.vultisig.com/1inch/`).
//
//  Rationale: keeps the SwapKit partner key off the iOS binary, avoids
//  per-platform key rotation, and lets the backend enforce platform-level
//  affiliate routing if it ever needs to.
//

import Foundation

enum SwapKitConfig {
    /// Base URL for SwapKit's V3 surface (quote + swap + providers) via the
    /// Vultisig proxy. The proxy forwards `/v3/quote`, `/v3/swap`,
    /// `/providers` 1:1 under the `/swapkit/` prefix.
    static let baseURL = URL(string: "https://api.vultisig.com/swapkit/v3")!

    /// `/track` lives off the bare host upstream (not under `/v3`), so the
    /// proxy mounts it at `/swapkit/track`. Keep separate so we can't
    /// accidentally double-prefix.
    static let trackBaseURL = URL(string: "https://api.vultisig.com/swapkit")!

    /// `Referer` header value the SwapKit partner dashboard uses to segment
    /// fee accounting by client. Sent through the proxy unchanged.
    static let referer = "vultisig-ios"

    /// Default request timeout. SwapKit responses observed sub-5s in the
    /// Phase 0 spike; the 30s budget leaves headroom for slower routes
    /// without blocking the UI.
    static let timeoutInterval: TimeInterval = 30

    /// Provider TTL — how long the cached `/providers` response is reused
    /// before re-fetching. 24h matches the design decision §4. Provider
    /// eligibility (which chains each provider supports) changes rarely —
    /// daily refresh is plenty.
    static let providerCacheTTL: TimeInterval = 24 * 60 * 60

    /// Token-catalog TTL — how long the cached `/tokens?provider=…` fan-out
    /// snapshot is reused before re-fetching. Shorter than `providerCacheTTL`
    /// because new tokens get added to NEAR Intents / Chainflip / etc.
    /// catalogs continuously, and a stale picker hides them. 5 min balances
    /// "user sees new tokens within a reasonable window" against "don't
    /// stampede the proxy every time the picker opens".
    static let tokensCacheTTL: TimeInterval = 5 * 60

    /// TTL for the swap "Select asset" picker's per-chain token list cache
    /// (`SwapTokenListCache` — the cached `TokenSearchService.loadTokens`
    /// output: 1inch / Jupiter + preset tokens). 6h: the curated + remote
    /// token catalogs change rarely, so a long window keeps re-selecting a
    /// chain fully offline (no spinner, no network) while still picking up
    /// catalog changes within a day. Tunable.
    static let swapTokenListCacheTTL: TimeInterval = 6 * 60 * 60

    /// Provider names that route through THORChain / MayaChain. Routes whose
    /// `providers[]` contain any of these are dropped at the fetcher
    /// boundary — Vultisig already routes those directly and we would
    /// otherwise pay both Vultisig's THORName affiliate fee and SwapKit's
    /// platform fee on the same swap.
    static let filteredProviders: Set<String> = [
        "THORCHAIN",
        "THORCHAIN_STREAMING",
        "MAYACHAIN",
        "MAYACHAIN_STREAMING"
    ]

    /// Gates SwapKit across the app — `swapProviders` list inclusion and
    /// `SwapKitService.fetchBestRoute`. SwapKit has shipped and is always
    /// enabled; the former Settings → Advanced opt-out toggle has been
    /// removed. The property is kept as a single source of truth so the
    /// call sites retain one gate if we ever need to dark-launch a change.
    static var isFeatureEnabled: Bool {
        true
    }
}
