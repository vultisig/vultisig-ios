//
//  ThorchainAccountValue.swift
//  VultisigApp
//
//  Created by Johnny Luo on 2/4/2024.
//

import Foundation

class THORChainAccountValue: Codable {
    var address: String?
    var publicKey: String?
    var accountNumber: String?
    var sequence: String?

    enum CodingKeys: String, CodingKey {
        case address, publicKey = "pub_key", accountNumber = "account_number", sequence
    }
}
