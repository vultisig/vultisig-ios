//
//  DeviceUnregisterRequest.swift
//  VultisigApp
//

import Foundation

struct DeviceUnregisterRequest: Codable {
    let vaultId: String
    let partyName: String

    enum CodingKeys: String, CodingKey {
        case vaultId = "vault_id"
        case partyName = "party_name"
    }
}
