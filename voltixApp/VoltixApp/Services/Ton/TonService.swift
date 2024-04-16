//
//  TonService.swift
//  VoltixApp
//
//  Created by Enrique Souza Soares on 15/04/2024.
//

import Foundation

import SwiftUI

class TonService {
    static let shared = TonService()
    private init() {}
    
    func getBalance(coin: Coin) async throws -> (rawBalance: String, priceRate: Double){
        
        let priceRateFiat = await CryptoPriceService.shared.getPrice(priceProviderId: coin.priceProviderId)
        
        let data = try await Utils.asyncGetRequest(urlString: Endpoint.fetchTonAccountBalance(address: coin.address), headers: [:])
        
        let rawBalance: String? = Utils.extractResultFromJson(fromData: data, path: "result") as? String
        
        return (rawBalance ?? "0", priceRateFiat)
    }
    
    func sendTransaction(encodedTransaction: String) async throws -> String? {
        
        let requestBody: [String: Any] = [
            "boc": encodedTransaction,
        ]
        
        let bodyData = try JSONSerialization.data(withJSONObject: requestBody, options: [])
        
        let data = try await Utils.asyncPostRequest(urlString: Endpoint.broadcastTonTransaction, headers: [:], body: bodyData)
        
        let result: String? = Utils.extractResultFromJson(fromData: data, path: "result") as? String
        
        return result
    }
}
