//
//  ThorchainBroadcastTransactionService.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 07/03/2024.
//

import Foundation

/// TargetType for the THORChain mainnet broadcast endpoint.
/// Stagenet / Chainnet equivalents will be introduced with their
/// respective service migrations.
enum ThorchainBroadcastAPI: TargetType {
    case broadcast(body: Data)

    var baseURL: URL { URL(string: "https://gateway.liquify.com/chain/thorchain_api")! }
    var path: String { "/cosmos/tx/v1beta1/txs" }
    var method: HTTPMethod { .post }
    var task: HTTPTask {
        switch self {
        case .broadcast(let body):
            return .requestData(body)
        }
    }
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
            let raw = try await httpClient.request(ThorchainBroadcastAPI.broadcast(body: jsonData))
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
