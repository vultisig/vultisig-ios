//
//  ThorchainBroadcastTransactionService.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 07/03/2024.
//

import Foundation

/// Pure `TargetType` for the THORChain mainnet broadcast endpoint. The
/// override-eligible LCD host (shared with the balance path) is baked in at
/// construction by `ThorchainService`; this value never consults global state.
/// Stagenet / Chainnet equivalents will be introduced with their respective
/// service migrations.
struct ThorchainBroadcastAPI: TargetType {
    let body: Data
    /// The resolved THORChain LCD host (override-aware), baked in by the service.
    let lcdHost: URL

    init(body: Data, lcdHost: URL = ThorchainMainnetAPI.defaultLCDHost) {
        self.body = body
        self.lcdHost = lcdHost
    }

    var baseURL: URL { lcdHost }
    var path: String { "/cosmos/tx/v1beta1/txs" }
    var method: HTTPMethod { .post }
    var task: HTTPTask { .requestData(body) }
    var headers: [String: String]? {
        ["Content-Type": "application/json"]
    }
}

extension ThorchainService {

    func broadcastTransaction(jsonString: String) async -> Result<String, Error> {
        guard let jsonData = jsonString.data(using: .utf8) else {
            return .failure(HelperError.runtimeError("fail to convert input json to data"))
        }

        do {
            let raw = try await httpClient.request(ThorchainBroadcastAPI(body: jsonData, lcdHost: resolvedLCDHost))
            let response = try JSONDecoder().decode(CosmosTransactionBroadcastResponse.self, from: raw.data)
            // code 0 = success; code 19 = already in mempool (idempotent success)
            if let code = response.txResponse?.code, code == 0 || code == 19 {
                if let txHash = response.txResponse?.txhash {
                    return .success(txHash)
                }
            }
            return .failure(HelperError.runtimeError(String(data: raw.data, encoding: .utf8) ?? "Unknown error"))
        } catch HTTPError.statusCode(let code, let data) {
            let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? "Unknown error"
            return .failure(HelperError.runtimeError("status code:\(code), \(body)"))
        } catch {
            return .failure(error)
        }
    }
}
