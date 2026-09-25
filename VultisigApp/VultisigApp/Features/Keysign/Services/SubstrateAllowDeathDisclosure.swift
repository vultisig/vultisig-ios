//
//  SubstrateAllowDeathDisclosure.swift
//  VultisigApp
//

import Foundation

/// What a co-signer is told about a DOT or TAO transfer whose initiator set
/// `allow_death`. Such a payload signs `transfer_allow_death` instead of the
/// keep-alive default, so it can empty the sender's account and destroy a
/// remainder below the existential deposit. The co-signer learns that only
/// from the payload, so this reads nothing else.
enum SubstrateAllowDeathDisclosure {

    static func isShown(for payload: KeysignPayload?) -> Bool {
        payload?.chainSpecific.polkadotAllowDeath ?? false
    }

    static func message(for payload: KeysignPayload?) -> String? {
        guard let payload, isShown(for: payload) else {
            return nil
        }
        return String(format: "allowDeathReapWarning".localized, payload.coin.ticker)
    }
}
