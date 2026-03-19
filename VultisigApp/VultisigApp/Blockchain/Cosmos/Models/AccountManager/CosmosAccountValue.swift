//
//  CosmosAccountValue.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 06/03/2024.
//

import Foundation

class CosmosAccountValue: Codable {
    var type: String
    var address: String?
    var accountNumber: String?
    var sequence: String?

    enum CodingKeys: String, CodingKey {
        case address, accountNumber = "account_number", sequence, type = "@type"
    }
}
