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
}
