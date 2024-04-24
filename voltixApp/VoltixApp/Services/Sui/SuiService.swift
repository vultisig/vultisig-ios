//
//  Sui.swift
//  VoltixApp
//
//  Created by Enrique Souza Soares on 24/04/24.
//

import Foundation
import SwiftUI
import BigInt
import WalletCore

class SuiService {
    static let shared = SuiService()
    private init() {}
    
    private var cacheFeePrice: [String: (data: BigInt, timestamp: Date)] = [:]
    private var cacheLatestCheckpointSequenceNumber: [String: (data: Int64, timestamp: Date)] = [:]
    private var cacheAllCoins: [String: (data: [TW_Sui_Proto_ObjectRef], timestamp: Date)] = [:]
    
    
    private let rpcURL = URL(string: Endpoint.suiServiceRpc)!
    private let jsonDecoder = JSONDecoder()
    
    func getGasInfo(coin: Coin) async throws -> BigInt {
        async let gasPrice = getReferenceGasPrice(coin: coin)
        return (try await gasPrice)
    }
    
    func getBalance(coin: Coin) async throws -> (rawBalance: String, priceRate: Double){
        var rawBalance = "0"
        let priceRateFiat = await CryptoPriceService.shared.getPrice(priceProviderId: coin.priceProviderId)
        
        do {
            let data = try await Utils.PostRequestRpc(rpcURL: rpcURL, method: "suix_getBalance", params:  [coin.address])
            
            if let totalBalance = Utils.extractResultFromJson(fromData: data, path: "result.totalBalance") as? String {
                rawBalance = totalBalance
            }
            
        } catch {
            print("Error fetching balance: \(error.localizedDescription)")
            throw error
        }
        return (rawBalance,priceRateFiat)
    }
    
    func getReferenceGasPrice(coin: Coin) async throws -> BigInt{
        let cacheKey = "\(coin.chain.name.lowercased())-getReferenceGasPrice"
        if let cachedData: BigInt = await Utils.getCachedData(cacheKey: cacheKey, cache: cacheFeePrice, timeInSeconds: 60*5) {
            return cachedData
        }
        
        do {
            let data = try await Utils.PostRequestRpc(rpcURL: rpcURL, method: "suix_getReferenceGasPrice", params:  [])
            if let result = Utils.extractResultFromJson(fromData: data, path: "result"),
               let resultString = result as? String {
                let intResult = resultString.toBigInt()
                self.cacheFeePrice[cacheKey] = (data: intResult, timestamp: Date())
                return intResult
            } else {
                print("JSON decoding error")
            }
        } catch {
            print("Error fetching balance: \(error.localizedDescription)")
            throw error
        }
        return BigInt.zero
    }
    
    func getAllCoins(coin: Coin) async throws -> [TW_Sui_Proto_ObjectRef]{
        let cacheKey = "\(coin.chain.name.lowercased())-\(coin.address)-suix_getAllCoins"
        if let cachedData: [TW_Sui_Proto_ObjectRef] = await Utils.getCachedData(cacheKey: cacheKey, cache: cacheAllCoins, timeInSeconds: 60*5) {
            return cachedData
        }
        
        do {
            let data = try await Utils.PostRequestRpc(rpcURL: rpcURL, method: "suix_getAllCoins", params:  [coin.address])
            if let coins: [SuiCoin] = Utils.extractResultFromJson(fromData: data, path: "result.data", type: [SuiCoin].self) {
                let allCoins = coins.map{
                    var coin = TW_Sui_Proto_ObjectRef()
                    coin.objectID = $0.coinObjectId
                    coin.version = UInt64($0.version) ?? UInt64.zero
                    coin.objectDigest = $0.digest
                    return coin
                }
                self.cacheAllCoins[cacheKey] = (data: allCoins, timestamp: Date())
                return allCoins
            } else {
                print("Failed to decode coins")
            }
        } catch {
            print("Error fetching balance: \(error.localizedDescription)")
            throw error
        }
        return []
    }
    
    func executeTransactionBlock(encodedTransaction: String) async throws -> String{
        do {
            let data = try await Utils.PostRequestRpc(rpcURL: rpcURL, method: "sui_executeTransactionBlock", params:  [encodedTransaction])
            
            if let result = Utils.extractResultFromJson(fromData: data, path: "result.digest"),
               let resultString = result as? NSString {
                let StringResult = resultString.description
                return StringResult
            } else {
                print("JSON decoding error")
            }
        } catch {
            print("Error fetching balance: \(error.localizedDescription)")
            throw error
        }
        return .empty
    }
}
