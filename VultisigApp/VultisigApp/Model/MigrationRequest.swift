//
//  MigrationRequest.swift
//  VultisigApp
//
//  Created by Johnny Luo on 18/3/2025.
//

import Foundation
struct MigrationRequest: Hashable,Codable {
    let public_key: String
    let session_id: String
    let hex_encryption_key: String
    let encryption_password: String
    let email: String
}
