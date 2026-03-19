//
//  ThorchainBroadcastTransactionService.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 07/03/2024.
//

import Foundation

extension ThorchainService {

func broadcastTransaction(jsonString: String) async -> Result<String, Error> {
        let url = URL(string: Endpoint.broadcastTransactionThorchainNineRealms)!

        guard let jsonData = jsonString.data(using: .utf8) else {
            return .failure(HelperError.runtimeError("fail to convert input json to data"))
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            let (data, resp)  =  try await URLSession.shared.data(for: request)
            guard let httpResponse = resp as? HTTPURLResponse else {
                return .failure(HelperError.runtimeError("Invalid http response"))
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                return .failure(HelperError.runtimeError("status code:\(httpResponse.statusCode), \(String(data: data, encoding: .utf8) ?? "Unknown error")"))
            }
            let response = try JSONDecoder().decode(CosmosTransactionBroadcastResponse.self, from: data)
            // Check if the transaction was successful based on the `code` field
            // code 19 means the transaction has been exist in the mempool , which indicate another party already broadcast successfully
            if let code = response.txResponse?.code, code == 0 || code == 19 {
                // Transaction successful
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
