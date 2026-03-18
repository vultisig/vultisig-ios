//
//  VaultCreateRequest.swift
//  VultisigApp
//
//  Created by Johnny Luo on 30/8/2024.
//

import Foundation

struct VaultCreateRequest: Hashable, Codable {
    let name: String
    let session_id: String
    let hex_encryption_key: String
    let hex_chain_code: String
    let local_party_id: String
    let encryption_password: String
    let email: String
    let lib_type: Int
}
