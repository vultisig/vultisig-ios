
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
    
    override func wasmTokenBalanceURL(contractAddress: String, base64Payload: String) -> URL? {
        return nil // Akash doesn't support WASM tokens
    }
    
    override func ibcDenomTraceURL(coin: Coin) -> URL? {
        return nil // Akash doesn't support IBC denom traces
    }
    
    override func latestBlockURL(coin: Coin) -> URL? {
        return nil // Not needed for Akash
    }
    
}
