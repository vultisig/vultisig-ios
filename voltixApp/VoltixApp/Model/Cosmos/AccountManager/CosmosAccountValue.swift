//
//  ThorchainAccountValue.swift
//  VoltixApp
//
//  Created by Enrique Souza Soares on 06/03/2024.
//

import Foundation

class CosmosAccountValue: Codable {
    var address: String?
    var publicKey: CosmosAccountValuePublicKey?
    var accountNumber: String?
    var sequence: String?
    
    enum CodingKeys: String, CodingKey {
        case address, publicKey = "pub_key", accountNumber = "account_number", sequence
    }
}

class CosmosAccountValuePublicKey: Codable {
    var type: String
    var value: String
}
