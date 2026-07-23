//
//  File.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 06/03/2024.
//

import Foundation

class CosmosBalanceResponse: Codable {
    var balances: [CosmosBalance]

    init(balances: [CosmosBalance]) {
        self.balances = balances
    }
}
