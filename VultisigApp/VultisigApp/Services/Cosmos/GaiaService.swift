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
    
    override func wasmTokenBalanceURL(contractAddress: String, base64Payload: String) -> URL? {
        return URL(string: Endpoint.fetchCosmosWasmTokenBalance(contractAddress: contractAddress, base64Payload: base64Payload))
    }
    
    override func ibcDenomTraceURL(coin: Coin)-> URL? {
        return URL(string: Endpoint.fetchCosmosIbcDenomTraces(hash: coin.contractAddress.replacingOccurrences(of: "ibc/", with: "")))
    }
    
    override func latestBlockURL(coin: Coin)-> URL? {
        return URL(string: Endpoint.fetchCosmosLatestBlock())
    }
    
    override func transactionStatusURL(txHash: String) -> URL? {
        return URL(string: Endpoint.fetchCosmosTransactionStatus(txHash: txHash))
    }
}
