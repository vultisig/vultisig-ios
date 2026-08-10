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

enum SuiBalanceError: Error, LocalizedError {
    case unparseableBalance(String)

    var errorDescription: String? {
        switch self {
        case .unparseableBalance(let raw):
            return "Sui returned an unparseable balance: \(raw)"
        }
    }
}

class SuiService: SuiCoinMetadataProviding {
    static let shared = SuiService()
    static let maximumCoinPages = 100

    private let logger = Log.chain.service

    /// Default Sui GraphQL RPC host.
    static let defaultRPCURL: URL = SuiGraphQLAPI.defaultHost

    /// Walks the resolved host list, failing over on transport faults only. The
    /// custom-RPC override is resolved per request, so a runtime override change
    /// is picked up live (the shared mirror updates without a relaunch).
    private let client: SuiFailoverClient

    init(
        resolver: RPCEndpointResolving = CustomRPCStore.shared,
        httpClient: HTTPClientProtocol = HTTPClient(),
        hosts: [URL] = SuiGraphQLAPI.defaultHosts
    ) {
        self.client = SuiFailoverClient(
            httpClient: httpClient,
            endpoints: SuiEndpointResolver(resolver: resolver, defaultHosts: hosts)
        )
    }

    func getGasInfo(coin: Coin) async throws -> (BigInt, [[String: String]]) {
        async let gasPrice = getReferenceGasPrice()
        async let allCoins = getAllCoins(coin: coin)
        return await (try gasPrice, try allCoins)
    }

    func getBalance(coin: CoinMeta, address: String) async throws -> String {
        return try await getAllBalances(coin: coin, address: address)
    }

    /// The balance of one coin type.
    ///
    /// `suix_getAllBalances` returned every coin type at once and the caller
    /// filtered; GraphQL exposes the balance of a named type directly, so it is
    /// asked for by name instead of paginating the whole `balances` connection
    /// and discarding all but one row.
    func getAllBalances(coin: CoinMeta, address: String) async throws -> String {
        let expectedCoinType = SuiCoinType.expectedType(
            isNativeToken: coin.isNativeToken,
            contractAddress: coin.contractAddress
        )

        let data = try await client.query(
            SuiGraphQLDocument.balance,
            variables: ["owner": address, "coinType": expectedCoinType],
            responseType: SuiBalanceData.self
        )

        // An address that has never held the coin type resolves to null rather
        // than an error — a genuine zero, not an upstream fault. A refusal
        // (malformed address, indexer outage) arrives as a populated `errors`
        // array and has already been raised by the transport.
        guard let totalBalance = data.address?.balance?.totalBalance else {
            return "0"
        }

        // A present-but-unparseable amount is a node contract violation, not an
        // empty wallet, so it is raised rather than shown to someone as a zero.
        guard BigInt(totalBalance) != nil else {
            throw SuiBalanceError.unparseableBalance(totalBalance)
        }

        return totalBalance
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

    /// The network's reference gas price.
    ///
    /// A missing or unparseable result throws rather than returning zero: a zero
    /// reference gas price silently under-prices the transaction that is built
    /// from it, which fails on chain instead of failing here.
    func getReferenceGasPrice() async throws -> BigInt {
        do {
            let data = try await client.query(
                SuiGraphQLDocument.referenceGasPrice,
                responseType: SuiEpochData.self
            )

            // `String.toBigInt()` answers zero for anything it cannot parse, so
            // it must not be used here: a zero price is indistinguishable from a
            // node returning garbage, and both under-price the transaction.
            // Sui's reference gas price is a positive protocol parameter, so
            // zero is never a legitimate answer either.
            guard let raw = data.epoch?.referenceGasPrice,
                  let price = BigInt(raw),
                  price > .zero else {
                throw Errors.missingReferenceGasPrice
            }

            return price
        } catch {
            logger.error("Error fetching reference gas price: \(error.localizedDescription, privacy: .public)")
            throw error
        }
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

                let data = try await client.query(
                    SuiGraphQLDocument.allCoins,
                    variables: ["owner": address, "cursor": cursor ?? NSNull()],
                    responseType: SuiCoinObjectsData.self
                )

                // Every part of the page is required. A missing connection, a
                // missing `pageInfo` or a missing `nodes` list are all node
                // contract violations, and reading any of them as "an empty but
                // valid page" would end the walk early and hand back a truncated
                // coin set — which `SuiHelper` then turns into a transaction
                // missing its gas object or its token objects. Fail loudly
                // instead; that is what this whole function is shaped around.
                guard let page = data.address?.objects,
                      let pageInfo = page.pageInfo,
                      let hasNextPage = pageInfo.hasNextPage,
                      let nodes = page.nodes else {
                    throw Errors.coinPageDecodeFailed(cursor: cursor)
                }
                coins.append(contentsOf: try Self.coins(from: nodes, cursor: cursor))

                guard hasNextPage else { break }
                guard let nextCursor = pageInfo.endCursor,
                      !nextCursor.isEmpty,
                      seenCursors.insert(nextCursor).inserted else {
                    throw Errors.invalidCoinPageCursor(cursor: pageInfo.endCursor)
                }
                cursor = nextCursor
            } while true

            return coins
        } catch {
            logger.error("Error fetching coins: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    /// Maps one page of the coin-object connection onto the model the rest of the
    /// app already speaks.
    ///
    /// The connection reports the wrapper struct `0x2::coin::Coin<T>`, so the
    /// type is unwrapped and address-normalized here — at the boundary, before
    /// anything downstream compares or persists it.
    ///
    /// Every field is required and a node that cannot be fully represented
    /// aborts the whole fetch. Dropping it instead would silently shrink the
    /// coin set, which is the same truncation the pagination guards exist to
    /// prevent — except harder to notice, because the page count would look
    /// right. `SuiHelper` needs the object id, version and digest to build an
    /// object reference and the balance to select inputs; an empty string for
    /// any of them produces an invalid transaction rather than a smaller one.
    private static func coins(
        from nodes: [SuiCoinObjectsData.Node],
        cursor: String?
    ) throws -> [SuiCoin] {
        try nodes.map { node in
            guard let repr = node.contents?.type?.repr,
                  let coinType = SuiCoinType.unwrap(repr),
                  let coinObjectId = node.address, !coinObjectId.isEmpty,
                  // `UInt53` arrives as a JSON number where JSON-RPC sent a
                  // decimal string; `SuiHelper` parses it back with `UInt64(_:)`,
                  // so the round trip is exact.
                  let version = node.version,
                  let digest = node.digest, !digest.isEmpty,
                  let balance = node.contents?.json?.balance, !balance.isEmpty else {
                throw Errors.coinPageDecodeFailed(cursor: cursor)
            }

            return SuiCoin(
                coinType: coinType,
                coinObjectId: coinObjectId,
                version: String(version),
                digest: digest,
                balance: balance
            )
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
        let data = try await client.query(
            SuiGraphQLDocument.coinMetadata,
            variables: ["coinType": coinType],
            responseType: SuiCoinMetadataData.self
        )

        // A null result is the node's answer for a coin that publishes no
        // metadata object, and is distinct from a node failure — only the latter
        // may abort, and the transport has already raised it, so a transient
        // outage is never read as "this coin has no metadata".
        guard let metadata = data.coinMetadata else { return nil }

        // `decimals` and `symbol` are required: a coin the node cannot describe
        // must be dropped rather than shown at a guessed magnitude or under a
        // placeholder ticker.
        guard let decimals = metadata.decimals, let symbol = metadata.symbol else {
            return nil
        }

        return SuiCoinMetadata(decimals: decimals, symbol: symbol, iconUrl: metadata.iconUrl)
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

    /// Broadcasts an already-signed transaction. `unsignedTransaction` is the
    /// base64 BCS `TransactionData` and `signature` the base64 submit-format
    /// envelope; both are forwarded verbatim — nothing here re-encodes signed
    /// material.
    func executeTransactionBlock(unsignedTransaction: String, signature: String) async throws -> String {
        let data = try await client.query(
            SuiGraphQLDocument.executeTransaction,
            variables: ["txBytes": unsignedTransaction, "signatures": [signature]],
            responseType: SuiExecuteTransactionData.self
        )

        guard let effects = data.executeTransaction?.effects else {
            throw Errors.missingTransactionDigest
        }

        // A rejected broadcast surfaces as a populated `errors` array, already
        // raised by the transport. An *executed* transaction that aborted on
        // chain reports it here instead. Fail closed on both — and on a status
        // we do not recognise, because returning a digest for a transaction we
        // cannot confirm executed would persist it and poll it as real.
        switch effects.outcome {
        case .succeeded:
            break
        case .failed:
            throw Errors.broadcastFailed(effects.failureReason ?? "transaction failed")
        case .undetermined:
            throw Errors.broadcastFailed(
                "unrecognized execution status: \(effects.status ?? "<absent>")"
            )
        }

        guard let digest = effects.digest, !digest.isEmpty else {
            throw Errors.missingTransactionDigest
        }

        return digest
    }

    /// Simulates a transaction to get accurate gas estimates
    /// - Parameter transactionBytes: Base64 encoded transaction bytes
    /// - Returns: Tuple of (computationCost, storageCost)
    func dryRunTransaction(transactionBytes: String) async throws -> (computationCost: BigInt, storageCost: BigInt) {
        do {
            // The BCS bytes travel inside a JSON-encoded `sui.rpc.v2.Transaction`
            // rather than as a bare base64 argument, but they are the SAME bytes
            // the JSON-RPC dry run took — passed through verbatim, so the
            // simulated transaction stays byte-identical to the signed one.
            let data = try await client.query(
                SuiGraphQLDocument.simulateTransaction,
                variables: ["tx": SuiGraphQLDocument.bcsTransaction(transactionBytes)],
                responseType: SuiSimulateTransactionData.self
            )

            guard let effects = data.simulateTransaction?.effects else {
                throw Errors.failedToParseGasEstimate
            }

            // A refused simulation arrives as a populated `errors` array, already
            // raised by the transport. A simulation that ran and aborted reports
            // it here instead — the node's verdict either way, not a parse
            // failure.
            //
            // The gas summary is only trustworthy for a simulation that actually
            // succeeded. A `FAILURE` can still carry costs, and an absent or
            // unrecognised status says nothing at all; consuming either would
            // price a transaction the node just told us will not execute, and
            // that estimate goes on to be signed.
            switch effects.outcome {
            case .succeeded:
                break
            case .failed:
                throw Errors.simulationFailed(effects.failureReason ?? "transaction failed")
            case .undetermined:
                throw Errors.simulationFailed(
                    "unrecognized execution status: \(effects.status ?? "<absent>")"
                )
            }

            guard let gasSummary = effects.gasEffects?.gasSummary,
                  let computation = gasSummary.computationCost,
                  let storage = gasSummary.storageCost else {
                throw Errors.failedToParseGasEstimate
            }

            return (BigInt(computation), BigInt(storage))
        } catch let error as Errors {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            logger.error("Error in dry run transaction: \(error.localizedDescription, privacy: .public)")
            throw Errors.dryRunFailed(error.localizedDescription)
        }
    }
}

private extension SuiService {

    enum Errors: Error, LocalizedError {
        case simulationFailed(String)
        case failedToParseGasEstimate
        case dryRunFailed(String)
        case coinPageDecodeFailed(cursor: String?)
        case invalidCoinPageCursor(cursor: String?)
        case coinPageLimitExceeded(maximum: Int)
        case broadcastFailed(String)
        case missingTransactionDigest
        case missingReferenceGasPrice

        var errorDescription: String? {
            switch self {
            case .simulationFailed(let error):
                return "Simulation Error: \(error)"
            case .failedToParseGasEstimate:
                return "Failed to parse gas estimate from dry run"
            case .dryRunFailed(let error):
                return "Dry run failed: \(error)"
            case .coinPageDecodeFailed(let cursor):
                return "Failed to decode the Sui coin-object page at cursor \(cursor ?? "<start>"). Aborting to avoid a truncated coin set."
            case .invalidCoinPageCursor(let cursor):
                return "Sui coin page returned an invalid cursor: \(cursor ?? "<nil>")"
            case .coinPageLimitExceeded(let maximum):
                return "Sui coin pagination exceeded the safety limit of \(maximum) pages"
            case .broadcastFailed(let error):
                return "Sui broadcast failed: \(error)"
            case .missingTransactionDigest:
                return "Sui broadcast did not return a transaction digest"
            case .missingReferenceGasPrice:
                return "Sui did not return a reference gas price"
            }
        }
    }
}
