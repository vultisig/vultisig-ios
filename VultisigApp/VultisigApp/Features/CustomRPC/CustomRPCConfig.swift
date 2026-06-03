//
//  CustomRPCConfig.swift
//  VultisigApp
//
//  Configuration for the Custom RPC feature. Mirrors `SwapKitConfig` /
//  `QBTCConfig`'s `isFeatureEnabled` shape so the Custom RPC entry in the
//  General settings section gates against a single source of truth.
//

import Foundation

enum CustomRPCConfig {
    /// Advanced-settings opt-in flag (Settings → Advanced → "Custom RPC").
    /// When `false`, the Custom RPC row is filtered out of the General
    /// settings section. The key is the same `@AppStorage` value
    /// `SettingsViewModel.customRPCEnabled` writes to, so the toggle and this
    /// read share one source of truth. Default `false` — opt-in while we
    /// develop + smoke-test.
    static var isFeatureEnabled: Bool {
        UserDefaults.standard.bool(forKey: "customRPCEnabled")
    }
}
