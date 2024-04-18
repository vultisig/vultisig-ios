//
//  Kujira.swift
//  VoltixApp
//
//  Created by Enrique Souza Soares on 17/04/2024.
//

import Foundation

class KujiraService: CosmosService {
    static let shared = KujiraService()
    
    override func balanceURL(forAddress address: String) -> URL? {
        return URL(string: Endpoint.fetchKujiraAccountBalance(address: address))
    }
    
    override func accountNumberURL(forAddress address: String) -> URL? {
        return URL(string: Endpoint.fetchKujiraAccountNumber(address))
    }
    
    override func transactionURL() -> URL? {
        return URL(string: Endpoint.broadcastKujiraTransaction)
    }
}
