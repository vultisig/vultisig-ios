//
//  MayaChainService.swift
//  VultisigApp
//
//  Created by Johnny Luo on 17/4/2024.
//

import Foundation

class MayachainService: ThorchainSwapProvider {
    static let shared = MayachainService()

    private init() {}

    func fetchBalances(_ address: String) async throws -> [CosmosBalance] {
        guard
            let url = URL(
                string: Endpoint.fetchAccountBalanceMayachain(address: address))
        else {
            return [CosmosBalance]()
        }
        let (data, _) = try await URLSession.shared.data(
            for: get9RRequest(url: url))

        let balanceResponse = try JSONDecoder().decode(
            CosmosBalanceResponse.self, from: data)
        return balanceResponse.balances
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

    func fetchAccountNumber(_ address: String) async throws
        -> THORChainAccountValue? {
        guard
            let url = URL(string: Endpoint.fetchAccountNumberMayachain(address))
        else {
            return nil
        }
        let (data, _) = try await URLSession.shared.data(
            for: get9RRequest(url: url))
        let accountResponse = try JSONDecoder().decode(
            THORChainAccountNumberResponse.self, from: data)
        return accountResponse.result.value
    }
    func get9RRequest(url: URL) -> URLRequest {
        var req = URLRequest(url: url)
        req.addValue("vultisig", forHTTPHeaderField: "X-Client-ID")
        return req
    }

    func fetchSwapQuotes(
        address: String,
        fromAsset: String,
        toAsset: String,
        amount: String,
        interval: Int,
        referredCode: String,
        vultTierDiscount: Int
    ) async throws -> ThorchainSwapQuote {

        let url = Endpoint.fetchSwapQuoteThorchain(
            chain: .maya,
            address: address,
            fromAsset: fromAsset,
            toAsset: toAsset,
            amount: amount,
            interval: String(interval),
            referredCode: referredCode,
            vultTierDiscount: vultTierDiscount
        )

        let (data, _) = try await URLSession.shared.data(
            for: get9RRequest(url: url))

        do {
            let response = try JSONDecoder().decode(
                ThorchainSwapQuote.self, from: data)
            return response
        } catch {
            let error = try JSONDecoder().decode(
                MayachainSwapError.self, from: data)
            throw error
        }
    }

    func broadcastTransaction(jsonString: String) async -> Result<String, Error> {
        let url = URL(string: Endpoint.broadcastTransactionMayachain)!

        guard let jsonData = jsonString.data(using: .utf8) else {
            return .failure(
                HelperError.runtimeError("fail to convert input json to data"))
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            let (data, resp) = try await URLSession.shared.data(for: request)
            guard let httpResponse = resp as? HTTPURLResponse else {
                return .failure(
                    HelperError.runtimeError("Invalid http response"))
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                return .failure(
                    HelperError.runtimeError(
                        "status code:\(httpResponse.statusCode), \(String(data: data, encoding: .utf8) ?? "Unknown error")"
                    ))
            }
            let response = try JSONDecoder().decode(
                CosmosTransactionBroadcastResponse.self, from: data)
            // Check if the transaction was successful based on the `code` field
            // code 19 means the transaction has been exist in the mempool , which indicate another party already broadcast successfully
            if let code = response.txResponse?.code, code == 0 || code == 19 {
                // Transaction successful
                if let txHash = response.txResponse?.txhash {
                    return .success(txHash)
                }
            }
            return .failure(
                HelperError.runtimeError(
                    String(data: data, encoding: .utf8) ?? "Unknown error"))

        } catch {
            return .failure(error)
        }

    }

    func getDepositAssets(completion: @escaping ([String]) -> Void) {
        let url = URL(string: Endpoint.depositAssetsMaya)!

        struct DepositAsset: Codable {
            let asset: String
            let bondable: Bool
        }

        let task = URLSession.shared.dataTask(with: URLRequest(url: url)) { data, response, error in
            // Verifica se houve erro
            if let error = error {
                print("Erro ao buscar ativos: \(error)")
                completion([])

                return
            }

            // Verifica se há dados
            guard let data = data else {
                completion([])

                return
            }

            do {
                let response = try JSONDecoder().decode(
                    [DepositAsset].self, from: data)
                let assets = response.filter { $0.bondable }.map { $0.asset }
                completion(assets)

            } catch {
                print("Erro ao decodificar dados: \(error)")
                completion([])

            }
        }

        task.resume()
    }

}
