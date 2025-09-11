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
    
    override func wasmTokenBalanceURL(contractAddress: String, base64Payload: String) -> URL? {
        return nil // DydX doesn't support WASM tokens
    }
    
    override func ibcDenomTraceURL(coin: Coin) -> URL? {
        return nil // DydX doesn't support IBC denom traces
    }
    
    override func latestBlockURL(coin: Coin) -> URL? {
        return nil // Not needed for DydX
    }
    
    override func transactionStatusURL(txHash: String) -> URL? {
        return URL(string: Endpoint.fetchDydxTransactionStatus(txHash: txHash))
    }
}
