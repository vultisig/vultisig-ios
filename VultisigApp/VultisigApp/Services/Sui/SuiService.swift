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
        let data = try await Utils.PostRequestRpc(
            rpcURL: rpcURL,
            method: "suix_getBalance",
            params:  [coin.address]
        )
        
        let allTokens = try await getAllTokensWithMetadata(coin: coin)
        
        
        guard let totalBalance = Utils.extractResultFromJson(
            fromData: data,
            path: "result.totalBalance"
        ) as? String else { throw Errors.getBalanceFailed }
        
        return totalBalance
    }
    
    func getAllBalances(coin: Coin) async throws -> String {
        let data = try await Utils.PostRequestRpc(
            rpcURL: rpcURL,
            method: "suix_getAllBalances",
            params:  [coin.address]
        )
        
        print(String(data: data, encoding: .utf8) ?? "")
        
        guard let totalBalance = Utils.extractResultFromJson(
            fromData: data,
            path: "result.totalBalance"
        ) as? String else { throw Errors.getBalanceFailed }
        
        return totalBalance
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
                let allCoins = coins.filter{ $0.coinType == "0x2::sui::SUI" }.map { coin in
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
    
    func getAllTokens(coin: Coin) async throws -> [[String: String]] {
        let cacheKey = "\(coin.chain.name.lowercased())-\(coin.address)-suix_getOwnedObjects"
        
        if let cachedData = await Utils.getCachedData(cacheKey: cacheKey, cache: cacheAllCoins, timeInSeconds: 60*5) {
            return cachedData
        }
        
        do {
            let data = try await Utils.PostRequestRpc(rpcURL: rpcURL, method: "suix_getOwnedObjects", params: [coin.address])
            
            if let objects: [[String: Any]] = Utils.extractResultFromJson(fromData: data, path: "result.data") as? [[String: Any]] {
                var tokens: [[String: String]] = []
                
                for obj in objects {
                    if let objData = obj["data"] as? [String: Any],
                       let objectId = objData["objectId"] as? String {
                        
                        // Fetch object details
                        let objectDetails = try await Utils.PostRequestRpc(rpcURL: rpcURL, method: "sui_getObject", params: [objectId, ["showContent": true]])
                        
                        if let coinType = Utils.extractResultFromJson(fromData: objectDetails, path: "result.data.content.type") as? String {
                            if let start = coinType.range(of: "<"), let end = coinType.range(of: ">") {
                                let extractedType = String(coinType[start.upperBound..<end.lowerBound])
                                tokens.append([
                                    "objectID": objectId,
                                    "coinType": extractedType
                                ])
                            }
                        }
                    }
                }
                
                self.cacheAllCoins.set(cacheKey, (data: tokens, timestamp: Date()))
                return tokens
            } else {
                print("Failed to decode owned objects")
            }
        } catch {
            print("Error fetching tokens: \(error.localizedDescription)")
            throw error
        }
        return []
    }
    
    func getAllTokensWithMetadata(coin: Coin) async throws -> [[String: String]] {
        let allTokens = try await getAllTokens(coin: coin) // Get tokens first
        
        var tokensWithMetadata: [[String: String]] = []
        
        for token in allTokens {
            if let objType = token["coinType"] {
                do {
                    
                    let metadata = try await Utils.PostRequestRpc(rpcURL: rpcURL, method: "suix_getCoinMetadata", params: [objType])
                    
                    print(String(data: metadata, encoding: .utf8) ?? "")
                    
                    let tokenData: [String: String] = [
                        "objectID": token["objectID"] ?? "",
                        "type": objType,
                        "symbol": Utils.extractResultFromJson(fromData: metadata, path: "result.symbol") as? String ?? "Unknown",
                        "name": Utils.extractResultFromJson(fromData: metadata, path: "result.name") as? String ?? "Unknown",
                        "decimals": Utils.extractResultFromJson(fromData: metadata, path: "result.decimals") as? String ?? "0",
                        "logo": Utils.extractResultFromJson(fromData: metadata, path: "result.iconUrl") as? String ?? ""
                    ]
                    
                    tokensWithMetadata.append(tokenData)
                } catch {
                    print("Error fetching metadata for \(objType): \(error.localizedDescription)")
                }
            }
        }
        
        return tokensWithMetadata
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

private extension SuiService {
    
    enum Errors: Error {
        case getBalanceFailed
    }
}
