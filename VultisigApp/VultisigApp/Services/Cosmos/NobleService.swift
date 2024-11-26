
//
//  OsmosisService.swift
//  VultisigApp
//
//  Created by Enrique Souza on 29/10/2024.
//

import Foundation

class NobleService: CosmosService {
    static let shared = NobleService()
    
    override func balanceURL(forAddress address: String) -> URL? {
        return URL(string: Endpoint.fetchNobleAccountBalance(address: address))
    }
    
    override func accountNumberURL(forAddress address: String) -> URL? {
        return URL(string: Endpoint.fetchNobleAccountNumber(address))
    }
    
    override func transactionURL() -> URL? {
        return URL(string: Endpoint.broadcastNobleTransaction)
    }
}
