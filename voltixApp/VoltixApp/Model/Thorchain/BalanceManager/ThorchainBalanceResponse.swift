//
//  File.swift
//  VoltixApp
//
//  Created by Enrique Souza Soares on 06/03/2024.
//

import Foundation

class ThorchainBalanceResponse: Codable {
    var balances: [ThorchainBalance]
    var pagination: ThorchainBalancePagination
    
    init(balances: [ThorchainBalance], pagination: ThorchainBalancePagination) {
        self.balances = balances
        self.pagination = pagination
    }
}
