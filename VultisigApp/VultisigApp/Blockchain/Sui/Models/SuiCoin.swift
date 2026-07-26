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
}
