//
//  CosmosServiceStruct.swift
//  VultisigApp
//

import Foundation
import OSLog

private let logger = Logger(subsystem: "com.vultisig.app", category: "cosmos-service")

struct CosmosServiceStruct {
    let config: CosmosServiceConfig
    private let httpClient: HTTPClientProtocol

    init(config: CosmosServiceConfig, httpClient: HTTPClientProtocol = HTTPClient()) {
        self.config = config
        self.httpClient = httpClient
    }

    // MARK: - Balance Operations

    func fetchBalances(coin: CoinMeta, address: String) async throws -> [CosmosBalance] {
        let usesNativeBalancesEndpoint = coin.isNativeToken
            || (!coin.isNativeToken && coin.contractAddress.contains("ibc/"))
            || (!coin.isNativeToken && coin.contractAddress.contains("factory/"))
            || (!coin.isNativeToken && !coin.contractAddress.contains("terra"))

        if usesNativeBalancesEndpoint {
            guard let baseURL = config.baseURL else {
                return []
            }

            let endpoint: CosmosAPI.Endpoint = config.usesSpendableBalances
                ? .spendableBalance(address: address)
                : .balance(address: address)

            let response = try await httpClient.request(
                CosmosAPI(baseURL: baseURL, endpoint: endpoint),
                responseType: CosmosBalanceResponse.self
            )
            return response.data.balances
        } else {
            let balance = try await fetchWasmTokenBalances(coin: coin, address: address)
            return [CosmosBalance(denom: coin.contractAddress, amount: balance)]
        }
    }

    // MARK: - IBC Operations

    func fetchIbcDenomTraces(coin: Coin) async -> CosmosIbcDenomTraceDenomTrace? {
        let hash = coin.contractAddress.replacingOccurrences(of: "ibc/", with: "")
        guard let baseURL = config.baseURL else {
            return nil
        }

        do {
            let response = try await httpClient.request(
                CosmosAPI(baseURL: baseURL, endpoint: .ibcDenomTrace(hash: hash)),
                responseType: CosmosIbcDenomTrace.self
            )

            if let denomTrace = response.data.denomTrace {
                return denomTrace
            } else if let error = response.data.error {
                logger.error("IBC denom trace: \(String(describing: error))")
            } else if let code = response.data.code, let message = response.data.message {
                logger.error("IBC denom trace - code: \(code), message: \(message)")
            }
            return nil
        } catch {
            return nil
        }
    }

    // MARK: - WASM Token Operations

    func fetchWasmTokenBalances(coin: CoinMeta, address: String) async throws -> String {
        let payload = "{\"balance\":{\"address\":\"\(address)\"}}"
        guard let base64Payload = payload.data(using: .utf8)?.base64EncodedString() else {
            return "0"
        }
        guard let baseURL = config.baseURL else {
            return "0"
        }

        // Pre-migration code returned "0" on any decode failure (via
        // Utils.extractResultFromJson); preserve that so balance screens keep
        // rendering 0 instead of surfacing a generic decoding error.
        do {
            let response = try await httpClient.request(
                CosmosAPI(baseURL: baseURL, endpoint: .wasmTokenBalance(contractAddress: coin.contractAddress, base64Payload: base64Payload)),
                responseType: CosmosWasmTokenBalanceResponse.self
            )
            return response.data.data.balance
        } catch HTTPError.decodingFailed(let error) {
            logger.warning("Wasm token balance decode failed for \(coin.contractAddress, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return "0"
        }
    }

    // MARK: - Block Operations

    func fetchLatestBlock() async throws -> String {
        guard let baseURL = config.baseURL else {
            return "0"
        }

        do {
            let response = try await httpClient.request(
                CosmosAPI(baseURL: baseURL, endpoint: .latestBlock),
                responseType: CosmosLatestBlockResponse.self
            )
            return response.data.block.header.height
        } catch HTTPError.decodingFailed(let error) {
            logger.warning("Latest block decode failed: \(error.localizedDescription, privacy: .public)")
            return "0"
        }
    }

    // MARK: - Terra Classic Tax

    /// Fetch Terra Classic's live `burn_tax_rate` from the `x/tax` module.
    /// Fails **closed**: any network/decode failure returns the conservative
    /// fallback rate so a transient LCD outage can't sign a zero-tax tx the
    /// chain then rejects at broadcast.
    func fetchTerraClassicBurnTaxRate() async -> Decimal {
        guard let baseURL = config.baseURL else {
            return TerraClassicTax.fallbackBurnTaxRate
        }

        do {
            let response = try await httpClient.request(
                CosmosAPI(baseURL: baseURL, endpoint: .terraClassicTaxParams),
                responseType: TerraClassicTaxParamsResponse.self
            )
            return TerraClassicTax.parseRate(response.data.params.burnTaxRate)
        } catch {
            logger.warning("Terra Classic burn tax rate fetch failed, using fallback: \(error.localizedDescription, privacy: .public)")
            return TerraClassicTax.fallbackBurnTaxRate
        }
    }

    // MARK: - Account Operations

    func fetchAccountNumber(_ address: String) async throws -> CosmosAccountValue? {
        guard let baseURL = config.baseURL else {
            return nil
        }

        let response = try await httpClient.request(
            CosmosAPI(baseURL: baseURL, endpoint: .accountNumber(address: address)),
            responseType: CosmosAccountsResponse.self
        )
        return response.data.account
    }

    // MARK: - Gas Simulation

    /// Estimate the gas a tx will consume via `/cosmos/tx/v1beta1/simulate`.
    /// `txBytes` is a base64-encoded protobuf `TxRaw` carrying a dummy signature
    /// (the node skips sig verification in simulate mode). Returns the node's
    /// reported `gas_info.gas_used`. Throws on any network/decode failure so the
    /// caller can fall back to the static gas limit — simulation must never
    /// block signing.
    func simulateGas(txBytes: String) async throws -> UInt64 {
        guard let baseURL = config.baseURL else {
            throw HelperError.runtimeError("No base URL for chain \(config.chain)")
        }

        let body = try JSONSerialization.data(withJSONObject: ["tx_bytes": txBytes], options: [])
        let response = try await httpClient.request(
            CosmosAPI(baseURL: baseURL, endpoint: .simulate(body: body)),
            responseType: CosmosSimulateResponse.self
        )

        guard let gasUsed = UInt64(response.data.gasInfo.gasUsed) else {
            throw HelperError.runtimeError("simulate returned non-numeric gas_used: \(response.data.gasInfo.gasUsed)")
        }
        return gasUsed
    }

    // MARK: - Transaction Operations

    func broadcastTransaction(jsonString: String) async -> Result<String, Error> {
        guard let baseURL = config.baseURL, let jsonData = jsonString.data(using: .utf8) else {
            return .failure(HelperError.runtimeError("Failed to convert input json to data"))
        }

        do {
            let raw = try await httpClient.request(
                CosmosAPI(baseURL: baseURL, endpoint: .broadcastTransaction(body: jsonData))
            )
            let response = try JSONDecoder().decode(CosmosTransactionBroadcastResponse.self, from: raw.data)
            let code = response.txResponse?.code
            let rawLog = response.txResponse?.rawLog
            if let code, code == 0 || code == 19 {
                if let txHash = response.txResponse?.txhash {
                    return .success(txHash)
                }
            }
            let responseBody = String(data: raw.data, encoding: .utf8) ?? "Unknown error"
            logger.error("Cosmos broadcast failed: code=\(code ?? -1), rawLog=\(rawLog ?? "nil"), body=\(responseBody)")
            return .failure(HelperError.runtimeError(responseBody))
        } catch HTTPError.statusCode(let code, let data) {
            let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? "Unknown error"
            return .failure(HelperError.runtimeError("Status code: \(code), \(body)"))
        } catch {
            return .failure(error)
        }
    }
}
