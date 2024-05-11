//
//  SuiCoin.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 24/04/24.
//

import Foundation

class SuiCoin: Codable {
    var coinType: String
    var coinObjectId: String
    var version: String
    var digest: String
    var balance: String
    var previousTransaction: String

    init(coinType: String, coinObjectId: String, version: String, digest: String, balance: String, previousTransaction: String) {
        self.coinType = coinType
        self.coinObjectId = coinObjectId
        self.version = version
        self.digest = digest
        self.balance = balance
        self.previousTransaction = previousTransaction
    }
}
