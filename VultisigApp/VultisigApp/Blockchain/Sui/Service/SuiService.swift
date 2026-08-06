//
//  Sui.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 24/04/24.
//

import Foundation
import SwiftUI
import BigInt
import OSLog
import WalletCore

struct SuiCoinMetadata: Decodable, Equatable {
    let decimals: Int
    let symbol: String
    let iconUrl: String?
}

protocol SuiCoinMetadataProviding {
    func getCoinMetadata(coinType: String) async throws -> SuiCoinMetadata?
}

enum SuiCoinMetadataError: Error {
    case rpc(String)
}

enum SuiBalanceError: Error {
    case rpc(String)
    case missingResult
}

class SuiService: SuiCoinMetadataProviding {
    static let shared = SuiService()
    static let maximumCoinPages = 100

    private let logger = Log.chain.service

    /// Default Sui JSON-RPC host.
    static let defaultRPCURL: URL = {
        guard let url = URL(string: Endpoint.suiServiceRpc) else {
            preconditionFailure("Invalid Sui default RPC URL: \(Endpoint.suiServiceRpc)")
        }
        return url
    }()

    /// Resolves the Sui custom RPC override. Injected so the request URL is
    /// derived from a dependency rather than a global reach-in; resolution is
    /// computed per access so a runtime override change is picked up live (the
    /// shared mirror updates without a relaunch).
    private let resolver: RPCEndpointResolving
    private let httpClient: HTTPClientProtocol

    init(
        resolver: RPCEndpointResolving = CustomRPCStore.shared,
        httpClient: HTTPClientProtocol = HTTPClient()
    ) {
        self.resolver = resolver
        self.httpClient = httpClient
    }

    /// The override-aware Sui JSON-RPC URL. Falls back to the default host when
    /// no override is set. Sui exposes a single JSON-RPC endpoint that the
    /// request methods post to directly, so the override is the complete URL.
    private var rpcURL: URL {
        resolver.resolvedURL(for: .sui, default: Self.defaultRPCURL)
    }

    func getGasInfo(coin: Coin) async throws -> (BigInt, [[String: String]]) {
        async let gasPrice = getReferenceGasPrice()
        async let allCoins = getAllCoins(coin: coin)
        return await (try gasPrice, try allCoins)
    }

    func getBalance(coin: CoinMeta, address: String) async throws -> String {
        return try await getAllBalances(coin: coin, address: address)
    }

    func getAllBalances(coin: CoinMeta, address: String) async throws -> String {
        let response = try await httpClient.request(
            SuiAPI(baseURL: rpcURL, endpoint: .allBalances(address: address)),
            responseType: SuiBalancesResponse.self
        )

        if let error = response.data.error {
            throw SuiBalanceError.rpc(error.message)
        }

        guard let balances = response.data.result else {
            throw SuiBalanceError.missingResult
        }

        let expectedCoinType = SuiCoinType.expectedType(
            isNativeToken: coin.isNativeToken,
            contractAddress: coin.contractAddress
        )
        return balances.first(where: {
            SuiCoinType.matches($0.coinType, expectedCoinType)
        })?.totalBalance ?? "0"
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

    func getReferenceGasPrice() async throws -> BigInt {
        do {
            let data = try await Utils.PostRequestRpc(rpcURL: rpcURL, method: "suix_getReferenceGasPrice", params: [])
            if let result = Utils.extractResultFromJson(fromData: data, path: "result"),
               let resultString = result as? String {
                let intResult = resultString.toBigInt()
                return intResult
            } else {
                logger.error("JSON decoding error")
            }
        } catch {
            logger.error("Error fetching balance: \(error.localizedDescription, privacy: .public)")
            throw error
        }
        return BigInt.zero
    }

    /// Fetches every coin object owned by the address.
    ///
    /// Returns all coin objects (every `coinType`) so callers can select the
    /// exact objects they need: the precise per-purpose selection — native SUI
    /// for a native send, the token's exact type plus SUI gas objects for a token
    /// send — happens downstream in `SuiHelper` by exact, normalized coin type.
    /// `suix_getAllCoins` is paginated (default page ~50), so we follow
    /// `nextCursor`/`hasNextPage` to avoid a truncated object set on heavy wallets.
    func getAllCoins(coin: Coin) async throws -> [[String: String]] {
        try await getAllCoinObjects(address: coin.address).map { suiCoin in
            [
                "objectID": suiCoin.coinObjectId,
                "version": suiCoin.version,
                "objectDigest": suiCoin.digest,
                "balance": suiCoin.balance,
                "coinType": suiCoin.coinType
            ]
        }
    }

    private func getAllCoinObjects(address: String) async throws -> [SuiCoin] {
        var coins: [SuiCoin] = []
        var cursor: String?
        var seenCursors = Set<String>()
        var pageCount = 0

        do {
            repeat {
                guard pageCount < Self.maximumCoinPages else {
                    throw Errors.coinPageLimitExceeded(maximum: Self.maximumCoinPages)
                }
                pageCount += 1

                let response = try await httpClient.request(
                    SuiAPI(baseURL: rpcURL, endpoint: .allCoins(address: address, cursor: cursor)),
                    responseType: SuiCoinPageResponse.self
                ).data

                if let error = response.error {
                    throw Errors.coinPageRPC(error.message)
                }

                guard let page = response.result else {
                    throw Errors.coinPageDecodeFailed(cursor: cursor)
                }
                coins.append(contentsOf: page.data)

                guard page.hasNextPage else { break }
                guard let nextCursor = page.nextCursor,
                      !nextCursor.isEmpty,
                      seenCursors.insert(nextCursor).inserted else {
                    throw Errors.invalidCoinPageCursor(cursor: page.nextCursor)
                }
                cursor = nextCursor
            } while true

            return coins
        } catch {
            logger.error("Error fetching coins: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    func getAllTokens(address: String) async throws -> [[String: String]] {
        let coinObjects = try await getAllCoinObjects(address: address)
        var seenTypes = Set<String>()

        return coinObjects
            .filter { !$0.coinType.isEmpty && !SuiCoinType.isNative($0.coinType) }
            .sorted { SuiCoinType.normalize($0.coinType) < SuiCoinType.normalize($1.coinType) }
            .compactMap { coin in
                let normalizedType = SuiCoinType.normalize(coin.coinType)
                guard seenTypes.insert(normalizedType).inserted else { return nil }
                return [
                    "objectID": coin.coinObjectId,
                    "coinType": coin.coinType
                ]
            }
    }

    func getCoinMetadata(coinType: String) async throws -> SuiCoinMetadata? {
        let response = try await httpClient.request(
            SuiAPI(baseURL: rpcURL, endpoint: .coinMetadata(coinType: coinType)),
            responseType: SuiCoinMetadataResponse.self
        )

        if let error = response.data.error {
            throw SuiCoinMetadataError.rpc(error.message)
        }

        return response.data.result
    }

    func getAllTokensWithMetadata(address: String) async throws -> [CoinMeta] {
        let allTokens = try await getAllTokens(address: address)
        var tokensWithMetadata: [CoinMeta] = []

        for token in allTokens {
            if let objType = token["coinType"] {
                if let curatedToken = TokensStore.TokenSelectionAssets.first(where: {
                    $0.chain == .sui &&
                        !$0.isNativeToken &&
                        !$0.contractAddress.isEmpty &&
                        SuiCoinType.matches($0.contractAddress, objType)
                }) {
                    tokensWithMetadata.append(curatedToken)
                    continue
                }

                do {
                    guard let metadata = try await getCoinMetadata(coinType: objType) else {
                        continue
                    }
                    let symbol = metadata.symbol.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !symbol.isEmpty, (0...255).contains(metadata.decimals) else { continue }

                    let coinMeta = CoinMeta(
                        chain: .sui,
                        ticker: symbol,
                        logo: metadata.iconUrl ?? .empty,
                        decimals: metadata.decimals,
                        priceProviderId: .empty,
                        contractAddress: SuiCoinType.normalize(objType),
                        isNativeToken: false
                    )

                    tokensWithMetadata.append(coinMeta)
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    logger.error("Error fetching metadata for \(String(describing: objType), privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }
        }

        return tokensWithMetadata
    }

    func executeTransactionBlock(unsignedTransaction: String, signature: String) async throws -> String {
        let data = try await Utils.PostRequestRpc(rpcURL: rpcURL, method: "sui_executeTransactionBlock", params: [unsignedTransaction, [signature]])

        // A non-success execution returns an `error.message`; throw it instead
        // of returning the text as a digest so a failed broadcast is never shown
        // as success or persisted/polled as a fake txid.
        if let error = Utils.extractResultFromJson(fromData: data, path: "error.message") as? String, !error.isEmpty {
            throw Errors.broadcastFailed(error)
        }

        guard let digest = Utils.extractResultFromJson(fromData: data, path: "result.digest") as? String, !digest.isEmpty else {
            throw Errors.missingTransactionDigest
        }

        return digest
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
            logger.error("Error in dry run transaction: \(error.localizedDescription, privacy: .public)")
            throw Errors.dryRunFailed(error.localizedDescription)
        }
    }
}

private struct SuiCoinMetadataResponse: Decodable {
    let result: SuiCoinMetadata?
    let error: SuiRPCError?
}

private struct SuiCoinPageResponse: Decodable {
    let result: SuiCoinPage?
    let error: SuiRPCError?
}

private struct SuiCoinPage: Decodable {
    let data: [SuiCoin]
    let nextCursor: String?
    let hasNextPage: Bool
}

private struct SuiBalancesResponse: Decodable {
    let result: [SuiBalance]?
    let error: SuiRPCError?
}

private struct SuiBalance: Decodable {
    let coinType: String
    let totalBalance: String
}

private struct SuiRPCError: Decodable {
    let message: String
}

private extension SuiService {

    enum Errors: Error, LocalizedError {
        case getBalanceFailed
        case simulationFailed(String)
        case failedToParseGasEstimate
        case dryRunFailed(String)
        case coinPageDecodeFailed(cursor: String?)
        case coinPageRPC(String)
        case invalidCoinPageCursor(cursor: String?)
        case coinPageLimitExceeded(maximum: Int)
        case broadcastFailed(String)
        case missingTransactionDigest

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
            case .coinPageDecodeFailed(let cursor):
                return "Failed to decode coin page from suix_getAllCoins at cursor \(cursor ?? "<start>"). Aborting to avoid a truncated coin set."
            case .coinPageRPC(let message):
                return "Sui coin page RPC failed: \(message)"
            case .invalidCoinPageCursor(let cursor):
                return "Sui coin page returned an invalid cursor: \(cursor ?? "<nil>")"
            case .coinPageLimitExceeded(let maximum):
                return "Sui coin pagination exceeded the safety limit of \(maximum) pages"
            case .broadcastFailed(let error):
                return "Sui broadcast failed: \(error)"
            case .missingTransactionDigest:
                return "Sui broadcast did not return a transaction digest"
            }
        }
    }
}
