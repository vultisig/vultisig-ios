//
//  DeviceRegistrationRequest.swift
//  VultisigApp
//

import Foundation

struct DeviceRegistrationRequest: Codable {
    let vaultId: String
    let partyName: String
    let token: String
    let deviceType: String

    enum CodingKeys: String, CodingKey {
        case vaultId = "vault_id"
        case partyName = "party_name"
        case token
        case deviceType = "device_type"
    }
}
