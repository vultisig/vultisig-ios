//
//  ResendVaultShareRequest.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 29/08/2025.
//

struct ResendVaultShareRequest: Codable {
    enum CodingKeys: String, CodingKey {
        case pubKeyECDSA = "public_key_ecdsa"
        case email
        case password
    }

    let pubKeyECDSA: String
    let email: String
    let password: String
}
