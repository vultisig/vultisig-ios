//
//  Sui.swift
//  VultisigApp
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
    
    private var cacheFeePrice: ThreadSafeDictionary<String, (data: BigInt, timestamp: Date)> = ThreadSafeDictionary()
    private var cacheLatestCheckpointSequenceNumber: ThreadSafeDictionary<String, (data: Int64, timestamp: Date)> = ThreadSafeDictionary()
    private var cacheAllCoins: ThreadSafeDictionary<String, (data: [[String:String]], timestamp: Date)> = ThreadSafeDictionary()
    
    private let rpcURL = URL(string: Endpoint.suiServiceRpc)!
    private let jsonDecoder = JSONDecoder()
    
    func getGasInfo(coin: Coin) async throws -> (BigInt, [[String:String]]) {
        async let gasPrice = getReferenceGasPrice(coin: coin)
        async let allCoins = getAllCoins(coin: coin)
        return await (try gasPrice, try allCoins)
    }
    
    func getBalance(coin: Coin) async throws -> String {
        var rawBalance = "0"
        
        do {
            let data = try await Utils.PostRequestRpc(rpcURL: rpcURL, method: "suix_getBalance", params:  [coin.address])
            
            if let totalBalance = Utils.extractResultFromJson(fromData: data, path: "result.totalBalance") as? String {
                rawBalance = totalBalance
            }
            
        } catch {
            print("Error fetching balance: \(error.localizedDescription)")
            throw error
        }
        return rawBalance
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
                self.cacheFeePrice.set(cacheKey, (data: intResult, timestamp: Date()))
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
    
    func getAllCoins(coin: Coin) async throws -> [[String:String]] {
        let cacheKey = "\(coin.chain.name.lowercased())-\(coin.address)-suix_getAllCoins"
        
        // Attempt to fetch cached data
        if let cachedData = await Utils.getCachedData(cacheKey: cacheKey, cache: cacheAllCoins, timeInSeconds: 60*5) {
            return cachedData
        }
        
        do {
            let data = try await Utils.PostRequestRpc(rpcURL: rpcURL, method: "suix_getAllCoins", params: [coin.address])
            if let coins: [SuiCoin] = Utils.extractResultFromJson(fromData: data, path: "result.data", type: [SuiCoin].self) {
                let allCoins = coins.filter{ $0.coinType == "0x2::sui::SUI" }.sorted(by: { $0.balance < $1.balance}).map { coin in
                    var coinDict = [String: String]()
                    coinDict["objectID"] = coin.coinObjectId.description
                    coinDict["version"] = String(coin.version) 
                    coinDict["objectDigest"] = coin.digest
                    coinDict["balance"] = String(coin.balance)
                    return coinDict
                }
                // Caching the transformed data instead of the raw data
                self.cacheAllCoins.set(cacheKey, (data: allCoins, timestamp: Date()))
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
    
    func executeTransactionBlock(unsignedTransaction: String, signature: String) async throws -> String{
        do {
            let data = try await Utils.PostRequestRpc(rpcURL: rpcURL, method: "sui_executeTransactionBlock", params:  [unsignedTransaction, [signature]])
            
            if let error = Utils.extractResultFromJson(fromData: data, path: "error.message") as? String {
                return error.description
            }
            
            if let result = Utils.extractResultFromJson(fromData: data, path: "result.digest") as? String {
                return result.description
            }
        } catch {
            return error.localizedDescription
        }
        return .empty
    }
}
