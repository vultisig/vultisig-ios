//
//  QBTCConfig.swift
//  VultisigApp
//
//  Configuration for the QBTC claim workstream. Every QBTC user-facing
//  surface — promo banner, Claim button, chain-picker entry, claim flow,
//  quantum-security onboarding hop, join-keysign QBTC fork — gates against
//  this single source of truth.
//
//  This gate is orthogonal to MLDSA keygen: MLDSA gates *keygen* (driven
//  by the QBTC claim flow), this gates QBTC *claim UI*.
//
//  QBTC claim is enabled for everyone — the former Settings → Advanced
//  opt-in toggle has been removed now that the workstream has shipped.
//

import Foundation

enum QBTCConfig {
    /// Gates every QBTC claim UI surface — promo banner, Claim button,
    /// chain-picker entry, claim flow, onboarding hop, join-keysign QBTC
    /// fork. Now that QBTC claim has shipped it is always enabled; the
    /// kill-switch is kept so the call sites retain a single source of
    /// truth if we ever need to dark-launch a follow-up change.
    static var isFeatureEnabled: Bool {
        true
    }
}
