//
//  SwapKitConfig.swift
//  VultisigApp
//
//  Configuration constants for the SwapKit aggregator integration.
//  The API key is read from `Bundle.main.infoDictionary["SwapKitAPIKey"]`,
//  which xcodegen wires from `VultisigApp.xcconfig` (gitignored) at build
//  time. As a development convenience, `SWAPKIT_API_KEY` from the process
//  environment is honoured when the Info.plist value is absent — useful for
//  CI / Xcode run schemes that inject the key as an env var.
//

import Foundation

enum SwapKitConfig {
    /// Base URL for the SwapKit V3 API. The trailing `/v3` is intentional —
    /// the `/v3/quote` and `/v3/swap` endpoints live here. `/track` is rooted
    /// at the parent host (see `SwapKitAPI.trackBaseURL`).
    static let baseURL = URL(string: "https://api.swapkit.dev/v3")!

    /// `/track` lives at the bare host, not under `/v3` — confirmed in the
    /// npm SDK and the SwapKit V3 docs. Keep these separate so we can't
    /// accidentally double-prefix.
    static let trackBaseURL = URL(string: "https://api.swapkit.dev")!

    /// `Referer` header value the SwapKit partner dashboard uses to segment
    /// fee accounting by client. Must stay in sync with the registered
    /// integrator name in the dashboard.
    static let referer = "vultisig-ios"

    /// Default request timeout. SwapKit responses observed sub-5s in the
    /// Phase 0 spike; the 30s budget leaves headroom for slower routes
    /// without blocking the UI.
    static let timeoutInterval: TimeInterval = 30

    /// Default slippage tolerance in percent. Mirrors the value the existing
    /// 1inch / Kyber integrations use.
    static let defaultSlippagePercent: Double = 0.5

    /// Provider TTL — how long the cached `/providers` response is reused
    /// before re-fetching. 24h matches the design decision §4.
    static let providerCacheTTL: TimeInterval = 24 * 60 * 60

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

    /// API key read at runtime. The Info.plist value is the production path
    /// (xcconfig → Info.plist substitution). The env var is a development
    /// fallback. Returning `nil` here means the integration is disabled at
    /// runtime — callers should treat that as "skip SwapKit" rather than
    /// raising an error visible to the user.
    static var apiKey: String? {
        if let value = Bundle.main.object(forInfoDictionaryKey: "SwapKitAPIKey") as? String,
           !value.isEmpty {
            return value
        }
        if let value = ProcessInfo.processInfo.environment["SWAPKIT_API_KEY"],
           !value.isEmpty {
            return value
        }
        return nil
    }
}
