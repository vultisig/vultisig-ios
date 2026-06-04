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
    /// Gates the Custom RPC row in the General settings section. Custom RPC
    /// has shipped and is always enabled; the former Settings → Advanced
    /// opt-in toggle has been removed. The property is kept as a single
    /// source of truth so the call site retains one gate if we ever need to
    /// dark-launch a change.
    static var isFeatureEnabled: Bool {
        true
    }
}
