//
//  DydxService.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 12/06/24.
//

import Foundation

class DydxService: CosmosService {
    static let shared = DydxService()
    
    override func balanceURL(forAddress address: String) -> URL? {
        return URL(string: Endpoint.fetchDydxAccountBalance(address: address))
    }
    
    override func accountNumberURL(forAddress address: String) -> URL? {
        return URL(string: Endpoint.fetchDydxAccountNumber(address))
    }
    
    override func transactionURL() -> URL? {
        return URL(string: Endpoint.broadcastDydxTransaction)
    }
}
