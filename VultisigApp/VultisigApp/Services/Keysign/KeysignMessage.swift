//
//  KeysignMessage.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 01.07.2024.
//

import Foundation

struct KeysignMessage: Codable, Hashable {
    var sessionID: String
    let serviceName: String
    let payload: KeysignPayload?
    let customMessagePayload: CustomMessagePayload?
    let encryptionKeyHex: String
    let useVultisigRelay: Bool
    let payloadID: String
    let customPayloadID: String
}
