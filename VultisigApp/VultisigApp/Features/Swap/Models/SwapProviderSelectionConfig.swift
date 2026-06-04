//
//  SwapProviderSelectionConfig.swift
//  VultisigApp
//
//  Single source of truth for the swap provider-selection feature gate.
//  Mirrors `SwapKitConfig.isFeatureEnabled`'s shape, but reads the
//  `@AppStorage("swapProviderSelectionEnabled")` toggle (Settings → Advanced)
//  off the same `UserDefaults` key so the swap VM and the settings row agree.
//
//  The flag is one of two conditions — the feature also requires the vault to
//  be Silver `VultDiscountTier` or above (resolved separately via the swap VM's
//  cached tier). Flag off OR below Silver → provider selection is invisible and
//  the best quote is auto-selected exactly as before.
//

import Foundation

enum SwapProviderSelectionConfig {
    /// `UserDefaults` key backing the `@AppStorage` toggle in `SettingsViewModel`.
    static let storageKey = "swapProviderSelectionEnabled"

    /// Whether the provider-selection toggle is on. Off by default — the row is
    /// only visible to Silver+ vaults and ships opt-in.
    static var isFeatureEnabled: Bool {
        UserDefaults.standard.bool(forKey: storageKey)
    }
}
