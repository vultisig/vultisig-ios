//
//  NotifyRequest.swift
//  VultisigApp
//

import Foundation

struct NotifyRequest: Codable {
    let vaultId: String
    let vaultName: String
    let localPartyId: String
    let qrCodeData: String

    enum CodingKeys: String, CodingKey {
        case vaultId = "vault_id"
        case vaultName = "vault_name"
        case localPartyId = "local_party_id"
        case qrCodeData = "qr_code_data"
    }
}
