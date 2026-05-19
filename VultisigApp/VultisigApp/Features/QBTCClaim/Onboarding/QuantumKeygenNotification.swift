//
//  QuantumKeygenNotification.swift
//  VultisigApp
//
//  Cross-flow signal fired when the user successfully generates their
//  vault's ML-DSA-44 key pair. Both the token-selection intercept (W2)
//  and the BTC chain-detail Claim banner (W3) listen for it so they
//  can complete their pending "add QBTC + show claim" follow-ups
//  without threading a closure through the keygen routes.
//

import Foundation

extension Notification.Name {
    /// Posted by `KeygenViewModel.startMldsaKeygen` immediately after the
    /// new MLDSA pubkey is persisted on the vault and the keygen status
    /// flips to `.KeygenFinished`. The user-info carries the vault's
    /// ECDSA pubkey so observers can correlate with their captured vault
    /// reference (vault objects are SwiftData `@Model`s and the
    /// notification crosses actor boundaries).
    static let qbtcQuantumKeygenCompleted = Notification.Name("qbtcQuantumKeygenCompleted")
}

enum QuantumKeygenNotification {
    /// Key under which the vault's `pubKeyECDSA` is stored on the
    /// notification's user-info dictionary.
    static let vaultPubKeyECDSAKey = "vaultPubKeyECDSA"

    /// Posts the completion notification. Call from `KeygenViewModel`
    /// after the MLDSA pubkey is saved.
    static func postCompleted(vaultPubKeyECDSA: String) {
        NotificationCenter.default.post(
            name: .qbtcQuantumKeygenCompleted,
            object: nil,
            userInfo: [vaultPubKeyECDSAKey: vaultPubKeyECDSA]
        )
    }
}
