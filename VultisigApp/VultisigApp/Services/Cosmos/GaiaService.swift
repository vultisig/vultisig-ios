//
//  GaiaService.swift
//  VultisigApp
//
//  Created by Johnny Luo on 1/4/2024.
//

import Foundation

class GaiaService: CosmosService {
    static let shared = GaiaService()
    
    override func balanceURL(forAddress address: String) -> URL? {
        return URL(string: Endpoint.fetchCosmosAccountBalance(address: address))
    }
    
    override func accountNumberURL(forAddress address: String) -> URL? {
        return URL(string: Endpoint.fetchCosmosAccountNumber(address))
    }
    
    override func transactionURL() -> URL? {
        return URL(string: Endpoint.broadcastCosmosTransaction)
    }
}
