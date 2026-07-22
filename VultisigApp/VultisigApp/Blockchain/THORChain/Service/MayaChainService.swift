//
//  MayaChainService.swift
//  VultisigApp
//
//  Created by Johnny Luo on 17/4/2024.
//

import Foundation
import OSLog

class MayachainService: ThorchainSwapProvider {
    static let shared = MayachainService()

    private let logger = Logger(subsystem: "com.vultisig.app", category: "mayachain-service")
    private let httpClient: HTTPClientProtocol
    private var cacheInboundAddresses = ThreadSafeDictionary<String, (data: [InboundAddress], timestamp: Date)>()

    /// Resolves the MayaChain custom RPC override. Injected so the API values
    /// are built from a dependency rather than a global reach-in; resolution
    /// happens per request inside `api(_:)` so a runtime override change is
    /// picked up live (the shared mirror updates without a relaunch).
    private let resolver: RPCEndpointResolving

    init(
        httpClient: HTTPClientProtocol = HTTPClient(),
        resolver: RPCEndpointResolving = CustomRPCStore.shared
    ) {
        self.httpClient = httpClient
        self.resolver = resolver
    }

    /// The override-aware Mayanode host. Falls back to the default host when no
    /// override is set.
    private var resolvedHost: URL {
        resolver.resolvedURL(for: .mayaChain, default: MayaChainAPI.defaultHost)
    }

    /// Builds a pure `MayaChainAPI` value with the resolved host baked in. The
    /// `TargetType` itself never consults the resolver.
    private func api(_ endpoint: MayaChainAPI.Endpoint) -> MayaChainAPI {
        MayaChainAPI(endpoint, host: resolvedHost)
    }

    func fetchBalances(_ address: String) async throws -> [CosmosBalance] {
        let response = try await httpClient.request(
            api(.balances(address: address)),
            responseType: CosmosBalanceResponse.self
        )
        return response.data.balances
    }

    func fetchTokens(_ address: String) async throws -> [CoinMeta] {
        do {
            let balances: [CosmosBalance] = try await fetchBalances(address)
            var coinMetaList = [CoinMeta]()
            for balance in balances where balance.denom.caseInsensitiveCompare("cacao") != .orderedSame {
                // Check if token exists in TokensStore first
                let localAsset = TokensStore.TokenSelectionAssets.first(where: {
                    $0.chain == .mayaChain && ($0.contractAddress == balance.denom || $0.ticker.uppercased() == balance.denom.uppercased())
                })

                let ticker: String
                let decimals: Int
                let logo: String
                let priceProviderId: String

                if let localAsset = localAsset {
                    // Use data from TokensStore
                    ticker = localAsset.ticker
                    decimals = localAsset.decimals
                    logo = localAsset.logo
                    priceProviderId = localAsset.priceProviderId
                } else {
                    // Fallback to basic metadata
                    ticker = balance.denom.uppercased()
                    decimals = 10 // MayaChain default decimals (CACAO uses 10)
                    logo = balance.denom.replacingOccurrences(of: "/", with: "").lowercased()
                    priceProviderId = ""
                }

                let coinMeta = CoinMeta(
                    chain: .mayaChain,
                    ticker: ticker,
                    logo: logo,
                    decimals: decimals,
                    priceProviderId: priceProviderId,
                    contractAddress: balance.denom,
                    isNativeToken: false
                )
                coinMetaList.append(coinMeta)
            }
            return coinMetaList
        } catch {
            logger.error("Error in fetchTokens: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    func fetchAccountNumber(_ address: String) async throws -> THORChainAccountValue? {
        let response = try await httpClient.request(
            api(.accountNumber(address: address)),
            responseType: THORChainAccountNumberResponse.self
        )
        return response.data.result.value
    }

    func fetchSwapQuotes(
        address: String,
        fromAsset: String,
        toAsset: String,
        amount: String,
        interval: Int,
        streamingQuantity: Int,
        liquidityToleranceBps: Int,
        referredCode: String,
        vultTierDiscount: Int
    ) async throws -> ThorchainSwapQuote {
        let (affiliate, affiliateBps) = MayachainService.affiliateParams(
            referredCode: referredCode,
            discountBps: vultTierDiscount
        )
        let streamingQuantityParam = streamingQuantity > 0 ? String(streamingQuantity) : nil

        let target = api(.swapQuote(
            fromAsset: fromAsset,
            toAsset: toAsset,
            amount: amount,
            destination: address,
            streamingInterval: String(interval),
            streamingQuantity: streamingQuantityParam,
            affiliate: affiliate,
            affiliateBps: affiliateBps,
            liquidityToleranceBps: liquidityToleranceBps > 0 ? String(liquidityToleranceBps) : nil
        ))

        // Maya sometimes returns a structured swap error body with a
        // non-2xx status or a shape that doesn't decode as ThorchainSwapQuote.
        // Fetch raw bytes once and try the success shape first, falling back
        // to the error shape — avoids a second round-trip on the error path.
        do {
            let raw = try await httpClient.request(target)
            if let quote = try? JSONDecoder().decode(ThorchainSwapQuote.self, from: raw.data) {
                return quote
            }
            throw try JSONDecoder().decode(MayachainSwapError.self, from: raw.data)
        } catch let error as HTTPError {
            if case .statusCode(_, let data?) = error,
               let swapError = try? JSONDecoder().decode(MayachainSwapError.self, from: data) {
                throw swapError
            }
            throw error
        }
    }

    func broadcastTransaction(jsonString: String) async -> Result<String, Error> {
        guard let jsonData = jsonString.data(using: .utf8) else {
            return .failure(HelperError.runtimeError("fail to convert input json to data"))
        }

        do {
            let raw = try await httpClient.request(api(.broadcast(body: jsonData)))
            let response = try JSONDecoder().decode(CosmosTransactionBroadcastResponse.self, from: raw.data)
            // Check if the transaction was successful based on the `code` field
            // code 19 means the transaction has been exist in the mempool, which indicates
            // another party already broadcast successfully.
            if let code = response.txResponse?.code, code == 0 || code == 19 {
                if let txHash = response.txResponse?.txhash {
                    return .success(txHash)
                }
            }
            return .failure(
                HelperError.runtimeError(String(data: raw.data, encoding: .utf8) ?? "Unknown error")
            )
        } catch HTTPError.statusCode(let code, let data) {
            let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? "Unknown error"
            return .failure(HelperError.runtimeError("status code:\(code), \(body)"))
        } catch {
            return .failure(error)
        }
    }

    func getDepositAssets() async -> [String] {
        struct DepositAsset: Codable {
            let asset: String
            let bondable: Bool
        }

        do {
            let response = try await httpClient.request(
                api(.pools),
                responseType: [DepositAsset].self
            )
            return response.data.filter { $0.bondable }.map { $0.asset }
        } catch {
            logger.error("Error fetching MayaChain deposit assets: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// Fetch MayaChain inbound addresses (halt flags + gas rates). Mirrors
    /// `ThorchainService.fetchThorchainInboundAddress`: 5-minute cache, fail-soft
    /// to an empty array on decode/network error. Pass `bypassCache: true` for the
    /// sign-time halt re-check, which must never read or write the cache.
    func fetchInboundAddress(bypassCache: Bool = false) async -> [InboundAddress] {
        do {
            return try await fetchInboundAddressOrThrow(bypassCache: bypassCache)
        } catch {
            logger.warning("MayaChain inbound address decoding error: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// Throwing variant of `fetchInboundAddress` for the sign-time fund-safety
    /// gate, which must fail CLOSED: a transport/decode failure has to propagate
    /// so a halt re-check can't be silently misread as "not halted". The fail-soft
    /// `fetchInboundAddress` wraps this for screen-level callers.
    func fetchInboundAddressOrThrow(bypassCache: Bool = false) async throws -> [InboundAddress] {
        let cacheKey = "mayachain-inbound-address"
        if !bypassCache,
           let cachedData = Utils.getCachedData(
               cacheKey: cacheKey,
               cache: cacheInboundAddresses,
               timeInSeconds: 60 * 5
           ) {
            return cachedData
        }
        let response = try await httpClient.request(
            api(.inboundAddresses),
            responseType: [InboundAddress].self
        )
        let inboundAddresses = response.data
        if !bypassCache {
            cacheInboundAddresses.set(cacheKey, (data: inboundAddresses, timestamp: Date()))
        }
        return inboundAddresses
    }

    /// Legacy callback shim. Existing call sites in FunctionCall views still use this
    /// signature; migrate them to the async variant above in a follow-up.
    func getDepositAssets(completion: @escaping ([String]) -> Void) {
        Task {
            let assets = await getDepositAssets()
            completion(assets)
        }
    }
}

private extension MayachainService {
    /// MayaChain only supports a single affiliate (no nested referral like THORChain).
    /// Returns (affiliateAddress, affiliateBps) as URL-param-ready strings, or (nil, nil)
    /// if no affiliate should be sent.
    static func affiliateParams(referredCode _: String, discountBps: Int) -> (String?, String?) {
        let feeRate = THORChainSwaps.discountedAffiliateBps(baseBps: THORChainSwaps.affiliateFeeRateBp, discountBps: discountBps)
        return (THORChainSwaps.affiliateFeeAddress, "\(feeRate)")
    }
}
