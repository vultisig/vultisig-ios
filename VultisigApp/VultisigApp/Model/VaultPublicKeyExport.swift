//
//  VaultPublicKeyExport.swift
//  VultisigApp
//
//  Created by Johnny Luo on 19/7/2024.
//

import Foundation

struct VaultPublicKeyExport: Codable, Hashable {
    let uid: String
    let name: String
    let public_key_ecdsa: String
    let public_key_eddsa: String
    let hex_chain_code: String
}
