
//
//  GaiaService.swift
//  VultisigApp
//
//  Created by Johnny Luo on 1/4/2024.
//

import Foundation

class AkashService: CosmosService {
    static let shared = AkashService()
    
    override func balanceURL(forAddress address: String) -> URL? {
        return URL(string: Endpoint.fetchAkashAccountBalance(address: address))
    }
    
    override func accountNumberURL(forAddress address: String) -> URL? {
        return URL(string: Endpoint.fetchAkashAccountNumber(address))
    }
    
    override func transactionURL() -> URL? {
        return URL(string: Endpoint.broadcastAkashTransaction)
    }
}
