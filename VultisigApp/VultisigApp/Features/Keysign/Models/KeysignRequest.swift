//
//  KeysignRequest.swift
//  VultisigApp
//
//  Created by Johnny Luo on 30/8/2024.
//

import Foundation

struct KeysignRequest: Hashable, Codable {
    let public_key: String // always use ecdsa
    let messages: [String]
    let session: String
    let hex_encryption_key: String
    let derive_path: String
    let is_ecdsa: Bool
    let vault_password: String
    let chain: String
    /// Routes Vultiserver into the MLDSA signing path — set for any chain whose
    /// `signingKeyType` is `.MLDSA` (e.g. QBTC send / staking). When false, the
    /// server picks ECDSA / EdDSA based on `is_ecdsa`. Without this flag, MLDSA
    /// requests are silently treated as EdDSA and the server-side MPC never
    /// starts — iOS sees an empty inbound-message poll forever. See vultiserver
    /// `internal/types/keysign.go`.
    let mldsa: Bool
}
