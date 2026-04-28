//
//  MayaChainService.swift
//  VultisigApp
//
//  Created by Johnny Luo on 17/4/2024.
//

import Foundation

class MayachainService: ThorchainSwapProvider {
    static let shared = MayachainService()

    private let httpClient: HTTPClientProtocol

    private init(httpClient: HTTPClientProtocol = HTTPClient()) {
        self.httpClient = httpClient
    }

    func fetchBalances(_ address: String) async throws -> [CosmosBalance] {
        let response = try await httpClient.request(
            MayaChainAPI.balances(address: address),
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
            print("Error in fetchTokens: \(error)")
            throw error
        }
    }

    func fetchAccountNumber(_ address: String) async throws -> THORChainAccountValue? {
        let response = try await httpClient.request(
            MayaChainAPI.accountNumber(address: address),
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
        referredCode: String,
        vultTierDiscount: Int
    ) async throws -> ThorchainSwapQuote {
        let (affiliate, affiliateBps) = MayachainService.affiliateParams(
            referredCode: referredCode,
            discountBps: vultTierDiscount
        )
        let streamingQuantityParam = streamingQuantity > 0 ? String(streamingQuantity) : nil

        do {
            let response = try await httpClient.request(
                MayaChainAPI.swapQuote(
                    fromAsset: fromAsset,
                    toAsset: toAsset,
                    amount: amount,
                    destination: address,
                    streamingInterval: String(interval),
                    streamingQuantity: streamingQuantityParam,
                    affiliate: affiliate,
                    affiliateBps: affiliateBps
                ),
                responseType: ThorchainSwapQuote.self
            )
            return response.data
        } catch HTTPError.decodingFailed, HTTPError.statusCode {
            // Maya sometimes returns a structured swap error body with a
            // non-2xx status or a shape that doesn't decode as ThorchainSwapQuote.
            // Re-fetch raw bytes and attempt the error decode.
            let raw = try await httpClient.request(MayaChainAPI.swapQuote(
                fromAsset: fromAsset,
                toAsset: toAsset,
                amount: amount,
                destination: address,
                streamingInterval: String(interval),
                streamingQuantity: streamingQuantityParam,
                affiliate: affiliate,
                affiliateBps: affiliateBps
            ))
            let swapError = try JSONDecoder().decode(MayachainSwapError.self, from: raw.data)
            throw swapError
        }
    }

    func broadcastTransaction(jsonString: String) async -> Result<String, Error> {
        guard let jsonData = jsonString.data(using: .utf8) else {
            return .failure(HelperError.runtimeError("fail to convert input json to data"))
        }

        do {
            let raw = try await httpClient.request(MayaChainAPI.broadcast(body: jsonData))
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
                MayaChainAPI.pools,
                responseType: [DepositAsset].self
            )
            return response.data.filter { $0.bondable }.map { $0.asset }
        } catch {
            print("Error fetching MayaChain deposit assets: \(error)")
            return []
        }
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
    static func affiliateParams(referredCode: String, discountBps: Int) -> (String?, String?) {
        let feeRate = max(0, THORChainSwaps.affiliateFeeRateBp - discountBps)
        return (THORChainSwaps.affiliateFeeAddress, "\(feeRate)")
    }
}
