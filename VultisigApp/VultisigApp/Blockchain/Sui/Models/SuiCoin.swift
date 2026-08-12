//
//  SuiCoin.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 24/04/24.
//

import Foundation

/// One Sui coin object, as the app needs it.
///
/// Not `Codable`: nothing decodes this any more. It is mapped by hand from the
/// GraphQL coin-object connection, and the keysign payload is built from the
/// five fields below rather than from an encoding of this type.
struct SuiCoin {
    let coinType: String
    let coinObjectId: String
    let version: String
    let digest: String
    let balance: String
}
