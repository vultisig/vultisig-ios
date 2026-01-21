//
//  ThorchainErrorResponse.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 07/03/2024.
//

import Foundation

class CosmosErrorResponse: Codable {
    let code: Int
    let message: String
    let details: [String]

    enum CodingKeys: String, CodingKey {
        case code, message, details
    }
}
