//
//  ThorchainAccountValue.swift
//  VoltixApp
//
//  Created by Enrique Souza Soares on 06/03/2024.
//

import Foundation

class ThorchainAccountValue: Codable {
    var address: String?
    var publicKey: ThorchainAccountValuePublicKey?
    var accountNumber: String?
    var sequence: String?
    
    enum CodingKeys: String, CodingKey {
        case address, publicKey = "public_key", accountNumber = "account_number", sequence
    }
}

class ThorchainAccountValuePublicKey: Codable {
    var type: String
    var value: String
}
