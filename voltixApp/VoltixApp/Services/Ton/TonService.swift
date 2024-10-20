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
    
    private var cacheBalance: [String: (data: (rawBalance: String, priceRate: Double), timestamp: Date)] = [:]
    
    func getBalance(coin: Coin) async throws -> (rawBalance: String, priceRate: Double){
        do {
            let cacheKey = "\(coin.chain.name.lowercased())-\(coin.address)-balance"
            if let (rawBalance, priceRate) = await Utils.getCachedData(cacheKey: cacheKey, cache: cacheBalance, timeInSeconds: 60) {
                return (rawBalance, priceRate)
            }
            
            let priceRateFiat = await CryptoPriceService.shared.getPrice(priceProviderId: coin.priceProviderId)
            
            let data = try await Utils.asyncGetRequest(urlString: Endpoint.fetchTonAccountBalance(address: coin.address), headers: [:])
            
            guard let rawBalance: String = Utils.extractResultFromJson(fromData: data, path: "result") as? String else {
                print("TonService > getBalance: error to Utils.extractResultFromJson")
                return (.zero, Double.zero)
            }
            
            self.cacheBalance[cacheKey] = (data: (rawBalance, priceRateFiat), timestamp: Date())
            
            return (rawBalance, priceRateFiat)
            
        } catch {
            print("TonService > getBalance \(error.localizedDescription)")
        }
        return (.zero, Double.zero)
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
