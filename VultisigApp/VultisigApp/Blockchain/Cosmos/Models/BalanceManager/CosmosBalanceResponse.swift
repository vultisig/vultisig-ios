//
//  File.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 06/03/2024.
//

import Foundation

class CosmosBalanceResponse: Codable {
    var balances: [CosmosBalance]
    var pagination: CosmosBalancePagination

    init(balances: [CosmosBalance], pagination: CosmosBalancePagination) {
        self.balances = balances
        self.pagination = pagination
    }
}
