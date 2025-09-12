
//
//  OsmosisService.swift
//  VultisigApp
//
//  Created by Enrique Souza on 29/10/2024.
//

import Foundation

class OsmosisService: CosmosService {
    static let shared = OsmosisService()
    
    override func balanceURL(forAddress address: String) -> URL? {
        return URL(string: Endpoint.fetchOsmosisAccountBalance(address: address))
    }
    
    override func accountNumberURL(forAddress address: String) -> URL? {
        return URL(string: Endpoint.fetchOsmosisAccountNumber(address))
    }
    
    override func transactionURL() -> URL? {
        return URL(string: Endpoint.broadcastOsmosisTransaction)
    }
    
    override func wasmTokenBalanceURL(contractAddress: String, base64Payload: String) -> URL? {
        return URL(string: Endpoint.fetchOsmosisWasmTokenBalance(contractAddress: contractAddress, base64Payload: base64Payload))
    }
    
    override func ibcDenomTraceURL(coin: Coin)-> URL? {
        return URL(string: Endpoint.fetchOsmosisIbcDenomTraces(hash: coin.contractAddress.replacingOccurrences(of: "ibc/", with: "")))
    }
    
    override func latestBlockURL(coin: Coin)-> URL? {
        return URL(string: Endpoint.fetchOsmosisLatestBlock())
    }
    
}
