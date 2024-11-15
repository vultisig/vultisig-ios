
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
    
    override func wasmTokenBalanceURL(contractAddress: String, base64Payload: String) -> URL? {
        return URL(string: Endpoint.fetchTerraWasmTokenBalance(contractAddress: contractAddress, base64Payload: base64Payload))
    }
    
    override func ibcDenomTraceURL(coin: Coin)-> URL? {
        return URL(string: Endpoint.fetchTerraIbcDenomTraces(hash: coin.contractAddress.replacingOccurrences(of: "ibc/", with: "")))
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
    
    override func wasmTokenBalanceURL(contractAddress: String, base64Payload: String) -> URL? {
        return URL(string: Endpoint.fetchTerraClassicWasmTokenBalance(contractAddress: contractAddress, base64Payload: base64Payload))
    }
    
    override func ibcDenomTraceURL(coin: Coin)-> URL? {
        return URL(string: Endpoint.fetchTerraClassicIbcDenomTraces(hash: coin.contractAddress.replacingOccurrences(of: "ibc/", with: "")))
    }
}
