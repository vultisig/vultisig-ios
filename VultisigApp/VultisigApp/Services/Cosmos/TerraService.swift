
//
//  TerraService.swift
//  VultisigApp
//
//  Created by Enrique Souza on 07/11/2024.
//

import Foundation

class TerraService: CosmosService {
    static let shared = TerraService()
    
    override func balanceURL(forAddress address: String) -> URL? {
        return URL(string: Endpoint.fetchTerraAccountBalance(address: address))
    }
    
    override func accountNumberURL(forAddress address: String) -> URL? {
        return URL(string: Endpoint.fetchTerraAccountNumber(address))
    }
    
    override func transactionURL() -> URL? {
        return URL(string: Endpoint.broadcastTerraTransaction)
    }
}

class TerraClassicService: CosmosService {
    static let shared = TerraClassicService()
    
    override func balanceURL(forAddress address: String) -> URL? {
        return URL(string: Endpoint.fetchTerraClassicAccountBalance(address: address))
    }
    
    override func accountNumberURL(forAddress address: String) -> URL? {
        return URL(string: Endpoint.fetchTerraClassicAccountNumber(address))
    }
    
    override func transactionURL() -> URL? {
        return URL(string: Endpoint.broadcastTerraClassicTransaction)
    }
}
