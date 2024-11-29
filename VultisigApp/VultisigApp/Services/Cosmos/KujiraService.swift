//
//  Kujira.swift
//  VultisigApp
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
    
    override func wasmTokenBalanceURL(contractAddress: String, base64Payload: String) -> URL? {
        return URL(string: Endpoint.fetchKujiraWasmTokenBalance(contractAddress: contractAddress, base64Payload: base64Payload))
    }
    
    override func ibcDenomTraceURL(coin: Coin)-> URL? {
        return URL(string: Endpoint.fetchKujiraIbcDenomTraces(hash: coin.contractAddress.replacingOccurrences(of: "ibc/", with: "")))
    }
    
    override func latestBlockURL(coin: Coin)-> URL? {
        return URL(string: Endpoint.fetchKujiraLatestBlock())
    }
}
