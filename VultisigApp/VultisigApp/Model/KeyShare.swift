//
//  KeyShare.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-04.
//

import Foundation

class KeyShare: Codable {
    let pubkey: String
    let keyshare: String
    let keyId: String?

    init(pubkey: String, keyshare: String, keyId: String? = nil) {
        self.pubkey = pubkey
        self.keyshare = keyshare
        self.keyId = keyId
    }

    /// Builds a share for storage, sealing the plaintext first.
    ///
    /// Every path that persists a share — keygen, reshare, key import, backup
    /// import — goes through here, so a share cannot reach storage unprotected
    /// by someone calling the plain initializer out of habit.
    static func sealed(
        pubkey: String,
        keyshare: String,
        keyId: String? = nil,
        protector: KeyshareProtecting = KeyshareProtector.shared
    ) throws -> KeyShare {
        KeyShare(
            pubkey: pubkey,
            keyshare: try protector.seal(keyshare),
            keyId: keyId
        )
    }
}
