//
//  ThorchainAccountValue.swift
//  VultisigApp
//
//  Created by Johnny Luo on 2/4/2024.
//

import Foundation


class THORChainAccountValue: Codable {
    var address: String?
    var publicKey: THORChainAccountValuePublicKey?
    var accountNumber: String?
    var sequence: String?
    
    enum CodingKeys: String, CodingKey {
        case address, publicKey = "public_key", accountNumber = "account_number", sequence
    }
}

class THORChainAccountValuePublicKey: Codable {
    var type: String
    var value: String
   
}
