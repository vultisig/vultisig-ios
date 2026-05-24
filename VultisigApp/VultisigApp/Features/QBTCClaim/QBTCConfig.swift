//
//  QBTCConfig.swift
//  VultisigApp
//
//  Configuration for the QBTC claim workstream. Mirrors `SwapKitConfig`'s
//  `isFeatureEnabled` shape so every QBTC user-facing surface — promo
//  banner, Claim button, chain-picker entry, claim flow, quantum-security
//  onboarding hop, join-keysign QBTC fork — gates against a single source
//  of truth.
//
//  The flag is independent of `isMLDSAEnabled`. MLDSA gates *keygen*; this
//  flag gates QBTC *claim UI*. Both need to be true for an end-to-end
//  claim, but the toggles are orthogonal.
//
//  Behaviour:
//  - New / existing installs default OFF — `UserDefaults.standard.bool(...)`
//    returns `false` for any unset key.
//  - Toggle in Settings → Advanced → "QBTC Claim".
//  - In-flight claim at flag-flip: the running keysign screen completes
//    naturally (we don't proactively pop a mid-session screen). New entry
//    points are blocked. Same precedent as SwapKit.
//  - Existing vault state preserved: if a user adds the QBTC chain with
//    the flag on and then flips it off, the QBTC `Coin` row stays on the
//    vault and any past QBTC claim tx in history remains visible. The
//    flag controls visibility of new entry points, not data lifecycle.
//

import Foundation

enum QBTCConfig {
    /// Advanced-settings opt-in flag (Settings → Advanced → "QBTC Claim").
    /// When `false`, every QBTC claim UI surface is hidden — promo banner,
    /// Claim button, chain-picker entry, claim flow, onboarding hop, join-
    /// keysign QBTC fork. Existing vault state (QBTC coin row, past claim
    /// tx history) is preserved — the flag controls UI visibility only.
    /// The key is the same `@AppStorage` value `SettingsViewModel.qbtcEnabled`
    /// writes to, so the toggle and this read share one source of truth.
    /// Default `false` — opt-in while we develop + smoke-test.
    static var isFeatureEnabled: Bool {
        UserDefaults.standard.bool(forKey: "qbtcEnabled")
    }
}
