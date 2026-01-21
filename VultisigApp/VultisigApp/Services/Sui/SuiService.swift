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

    private let rpcURL = URL(string: Endpoint.suiServiceRpc)!
    private let jsonDecoder = JSONDecoder()

    func getGasInfo(coin: Coin) async throws -> (BigInt, [[String: String]]) {
        async let gasPrice = getReferenceGasPrice(coin: coin)
        async let allCoins = getAllCoins(coin: coin)
        return await (try gasPrice, try allCoins)
    }

    func getBalance(coin: CoinMeta, address: String) async throws -> String {
        return try await getAllBalances(coin: coin, address: address)
    }

    func getAllBalances(coin: CoinMeta, address: String) async throws -> String {
        do {
            let data = try await Utils.PostRequestRpc(
                rpcURL: rpcURL,
                method: "suix_getAllBalances",
                params: [address]
            )

            if let result = Utils.extractResultFromJson(fromData: data, path: "result") as? [[String: Any]] {
                if let item = result.first(where: {
                    guard let coinType = $0["coinType"] as? String else { return false }
                    return coinType.lowercased().contains("\(coin.ticker.lowercased())")
                }),
                   let balance = item["totalBalance"] as? String {
                    return balance
                }
            }

            return "0"
        } catch {
            print("Error fetching suix_getAllBalances: \(error.localizedDescription)")
            return "0"
        }
    }

    /// Get token USD value with proper decimal handling
    /// - Parameters:
    ///   - contractAddress: Token contract address
    ///   - decimals: Token decimals (defaults to 9 for SUI native tokens)
    /// - Returns: Price in USD
    static func getTokenUSDValue(contractAddress: String, decimals: Int = 9) async -> Double {
        // First try to get price from Cetus aggregator with proper decimals
        let cetusPrice = await CetusAggregatorService.shared.getTokenUSDValue(contractAddress: contractAddress, decimals: decimals)

        if cetusPrice > 0 {
            return cetusPrice
        }

        // Fallback to the old pool-based method if Cetus doesn't return a price
        do {
            let urlString: String = Endpoint.suiTokenQuote()
            let dataResponse = try await Utils.asyncGetRequest(urlString: urlString, headers: [:])

            if let pools = Utils.extractResultFromJson(fromData: dataResponse, path: "data.pools") as? [[String: Any]] {

                let usdcAddress = SuiConstants.usdcAddress

                // Find a pool where `contractAddress` is in either `coin_a` or `coin_b`
                let pool = pools.first { pool in
                    guard
                        let coinA = pool["coin_a"] as? [String: Any],
                        let coinAAddress = coinA["address"] as? String,
                        let coinB = pool["coin_b"] as? [String: Any],
                        let coinBAddress = coinB["address"] as? String
                    else {
                        return false
                    }

                    return (coinAAddress.uppercased().contains(contractAddress.uppercased()) && coinBAddress.uppercased().contains(usdcAddress.uppercased())) ||
                           (coinBAddress.uppercased().contains(contractAddress.uppercased()) && coinAAddress.uppercased().contains(usdcAddress.uppercased()))
                }

                // If no pool is found, return 0.0
                guard let pool = pool else {
                    return 0.0
                }

                // Extract price
                if let priceString = pool["price"] as? String, let price = Double(priceString) {
                    guard let coinA = pool["coin_a"] as? [String: Any], let coinAAddress = coinA["address"] as? String else {
                        return 0.0
                    }

                    // If USDC is `coin_a`, invert the price
                    return coinAAddress.uppercased().contains(usdcAddress.uppercased()) ? (price > 0 ? 1 / price : 0.0) : price
                }
            }

            return 0.0

        } catch {
            return 0.0
        }
    }

    func getReferenceGasPrice(coin: Coin) async throws -> BigInt {
        do {
            let data = try await Utils.PostRequestRpc(rpcURL: rpcURL, method: "suix_getReferenceGasPrice", params: [])
            if let result = Utils.extractResultFromJson(fromData: data, path: "result"),
               let resultString = result as? String {
                let intResult = resultString.toBigInt()
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

    func getAllCoins(coin: Coin) async throws -> [[String: String]] {

        do {
            let data = try await Utils.PostRequestRpc(rpcURL: rpcURL, method: "suix_getAllCoins", params: [coin.address])

            if let coins: [SuiCoin] = Utils.extractResultFromJson(fromData: data, path: "result.data", type: [SuiCoin].self) {
                let allCoins = coins.filter { $0.coinType.uppercased().contains("SUI") || $0.coinType.uppercased().contains(coin.ticker.uppercased()) }.map { coin in
                    var coinDict = [String: String]()
                    coinDict["objectID"] = coin.coinObjectId.description
                    coinDict["version"] = String(coin.version)
                    coinDict["objectDigest"] = coin.digest
                    coinDict["balance"] = String(coin.balance)
                    coinDict["coinType"] = String(coin.coinType)
                    return coinDict
                }

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

    func getAllTokens(address: String) async throws -> [[String: String]] {

        do {
            let data = try await Utils.PostRequestRpc(rpcURL: rpcURL, method: "suix_getOwnedObjects", params: [address])

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

    func getAllTokensWithMetadata(address: String) async throws -> [CoinMeta] {
        let allTokens = try await getAllTokens(address: address) // Get tokens first

        var tokensWithMetadata: [CoinMeta] = []

        for token in allTokens {
            if let objType = token["coinType"] {
                do {

                    let metadata = try await Utils.PostRequestRpc(rpcURL: rpcURL, method: "suix_getCoinMetadata", params: [objType])

                    let tokenData: [String: String] = [
                        "objectID": token["objectID"] ?? "",
                        "type": objType,
                        "symbol": Utils.extractResultFromJson(fromData: metadata, path: "result.symbol") as? String ?? "Unknown",
                        "name": Utils.extractResultFromJson(fromData: metadata, path: "result.name") as? String ?? "Unknown",
                        "decimals": (Utils.extractResultFromJson(fromData: metadata, path: "result.decimals") as? Int ?? 0).description,
                        "logo": Utils.extractResultFromJson(fromData: metadata, path: "result.iconUrl") as? String ?? ""
                    ]

                    // Search TokensStore by ticker for any token with a valid priceProviderId
                    let knownTokenByTicker = TokensStore.TokenSelectionAssets.first { knownAsset in
                        knownAsset.ticker.uppercased() == tokenData["symbol"]?.uppercased() &&
                        !knownAsset.priceProviderId.isEmpty
                    }

                    let decimals = Int(tokenData["decimals"] ?? "0")!

                    let coinMeta = CoinMeta(
                        chain: .sui,
                        ticker: tokenData["symbol"]!,
                        logo: tokenData["logo"]!,
                        decimals: decimals,
                        priceProviderId: knownTokenByTicker?.priceProviderId ?? "", // Use price provider ID from any matching token
                        contractAddress: objType,
                        isNativeToken: tokenData["symbol"]! == TokensStore.Token.suiSUI.ticker ? true : false
                    )

                    tokensWithMetadata.append(coinMeta)
                } catch {
                    print("Error fetching metadata for \(objType): \(error.localizedDescription)")
                }
            }
        }

        return tokensWithMetadata.filter { $0.isNativeToken == false }
    }

    func executeTransactionBlock(unsignedTransaction: String, signature: String) async throws -> String {
        do {
            let data = try await Utils.PostRequestRpc(rpcURL: rpcURL, method: "sui_executeTransactionBlock", params: [unsignedTransaction, [signature]])

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

    /// Simulates a transaction to get accurate gas estimates
    /// - Parameter transactionBytes: Base64 encoded transaction bytes
    /// - Returns: Tuple of (computationCost, storageCost)
    func dryRunTransaction(transactionBytes: String) async throws -> (computationCost: BigInt, storageCost: BigInt) {
        do {
            let data = try await Utils.PostRequestRpc(
                rpcURL: rpcURL,
                method: "sui_dryRunTransactionBlock",
                params: [transactionBytes]
            )

            // Check for error first
            if let error = Utils.extractResultFromJson(fromData: data, path: "result.effects.status.error") as? String, !error.isEmpty {
                throw Errors.simulationFailed(error)
            }

            // Extract gas costs
            if let computationCostStr = Utils.extractResultFromJson(fromData: data, path: "result.effects.gasUsed.computationCost") as? String,
               let storageCostStr = Utils.extractResultFromJson(fromData: data, path: "result.effects.gasUsed.storageCost") as? String {

                let computationCost = computationCostStr.toBigInt()
                let storageCost = storageCostStr.toBigInt()

                return (computationCost, storageCost)
            }

            throw Errors.failedToParseGasEstimate
        } catch let error as Errors {
            throw error
        } catch {
            print("Error in dry run transaction: \(error.localizedDescription)")
            throw Errors.dryRunFailed(error.localizedDescription)
        }
    }
}

private extension SuiService {

    enum Errors: Error, LocalizedError {
        case getBalanceFailed
        case simulationFailed(String)
        case failedToParseGasEstimate
        case dryRunFailed(String)

        var errorDescription: String? {
            switch self {
            case .getBalanceFailed:
                return "Failed to get balance"
            case .simulationFailed(let error):
                return "Simulation Error: \(error)"
            case .failedToParseGasEstimate:
                return "Failed to parse gas estimate from dry run"
            case .dryRunFailed(let error):
                return "Dry run failed: \(error)"
            }
        }
    }
}
