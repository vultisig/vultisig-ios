//
//  CosmosServiceStruct.swift
//  VultisigApp
//
//  Refactored to use struct instead of classes
//

import Foundation

struct CosmosServiceStruct {
    let config: CosmosServiceConfig

    // MARK: - Balance Operations

    func fetchBalances(coin: CoinMeta, address: String) async throws -> [CosmosBalance] {
        if coin.isNativeToken
            || (!coin.isNativeToken && coin.contractAddress.contains("ibc/"))
            || (!coin.isNativeToken && coin.contractAddress.contains("factory/"))
            || (!coin.isNativeToken && !coin.contractAddress.contains("terra")) {
            guard let url = config.balanceURL(forAddress: address) else {
                return [CosmosBalance]()
            }

            let (data, _) = try await URLSession.shared.data(from: url)
            let balanceResponse = try JSONDecoder().decode(CosmosBalanceResponse.self, from: data)
            return balanceResponse.balances

        } else {
            let balance = try await fetchWasmTokenBalances(coin: coin, address: address)
            return [CosmosBalance(denom: coin.contractAddress, amount: balance)]
        }
    }

    // MARK: - IBC Operations

    func fetchIbcDenomTraces(coin: Coin) async -> CosmosIbcDenomTraceDenomTrace? {
        let hash = coin.contractAddress.replacingOccurrences(of: "ibc/", with: "")
        guard let url = config.ibcDenomTraceURL(hash: hash) else {
            return nil
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)

            let decoder = JSONDecoder()
            let response = try decoder.decode(CosmosIbcDenomTrace.self, from: data)

            if let denomTrace = response.denomTrace {
                return denomTrace
            } else if let error = response.error {
                print("Error fetching IBC denom traces: \(error)")
                // Handle "not implemented" error
                return nil
            } else if let code = response.code, let message = response.message {
                print("Error fetching IBC denom traces - Code: \(code), Message: \(message)")
                // Handle general error
                return nil
            } else {
                // Handle unexpected response
                return nil
            }
        } catch {
            // Return nil in case of any error
            return nil
        }
    }

    // MARK: - WASM Token Operations

    func fetchWasmTokenBalances(coin: CoinMeta, address: String) async throws -> String {
        let payload = "{\"balance\":{\"address\":\"\(address)\"}}"
        let base64Payload = payload.data(using: .utf8)?.base64EncodedString()

        guard let base64Payload else {
            return "0"
        }

        guard let url = config.wasmTokenBalanceURL(contractAddress: coin.contractAddress, base64Payload: base64Payload) else {
            return "0"
        }

        let (data, _) = try await URLSession.shared.data(from: url)

        if let balance = Utils.extractResultFromJson(fromData: data, path: "data.balance") as? String {
            return balance
        }

        return "0"
    }

    // MARK: - Block Operations

    func fetchLatestBlock(coin: Coin) async throws -> String {
        guard let url = config.latestBlockURL() else {
            return "0"
        }

        let (data, _) = try await URLSession.shared.data(from: url)

        if let block = Utils.extractResultFromJson(fromData: data, path: "block.header.height") as? String {
            return block
        }

        return "0"
    }

    // MARK: - Account Operations

    func fetchAccountNumber(_ address: String) async throws -> CosmosAccountValue? {
        guard let url = config.accountNumberURL(forAddress: address) else {
            return nil
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        let accountResponse = try JSONDecoder().decode(CosmosAccountsResponse.self, from: data)
        return accountResponse.account
    }

    // MARK: - Transaction Operations

    func broadcastTransaction(jsonString: String) async -> Result<String, Error> {
        guard let url = config.transactionURL(), let jsonData = jsonString.data(using: .utf8) else {
            return .failure(HelperError.runtimeError("Failed to convert input json to data"))
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            let (data, resp) = try await URLSession.shared.data(for: request)
            guard let httpResponse = resp as? HTTPURLResponse else {
                return .failure(HelperError.runtimeError("Invalid HTTP response"))
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                return .failure(HelperError.runtimeError("Status code: \(httpResponse.statusCode), \(String(data: data, encoding: .utf8) ?? "Unknown error")"))
            }
            let response = try JSONDecoder().decode(CosmosTransactionBroadcastResponse.self, from: data)
            if let code = response.txResponse?.code, code == 0 || code == 19 {
                if let txHash = response.txResponse?.txhash {
                    return .success(txHash)
                }
            }
            return .failure(HelperError.runtimeError(String(data: data, encoding: .utf8) ?? "Unknown error"))

        } catch {
            return .failure(error)
        }
    }
}
