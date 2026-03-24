//
//  BittensorTransactionStatusProvider.swift
//  VultisigApp
//

import Foundation

/// Bittensor Transaction Status Logic:
/// - Uses Taostats API for transaction status checking
/// - Endpoint: https://api.taostats.io/api/extrinsic/v1?hash={tx_hash}
/// - Checks `data[0].success` (bool) and `data[0].fee` (string)
struct BittensorTransactionStatusProvider: TransactionStatusProvider {

    func checkStatus(query: TransactionStatusQuery) async throws -> TransactionStatusResult {
        let txHash = query.txHash.hasPrefix("0x") ? query.txHash : "0x\(query.txHash)"
        let urlString = Endpoint.bittensorExtrinsicUrl(txHash: txHash)
        guard let url = URL(string: urlString) else {
            return TransactionStatusResult(status: .notFound, blockNumber: nil, confirmations: nil)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, _) = try await URLSession.shared.data(for: request)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataArray = json["data"] as? [[String: Any]] else {
            return TransactionStatusResult(status: .notFound, blockNumber: nil, confirmations: nil)
        }

        // Empty data array means transaction not found yet
        guard let first = dataArray.first else {
            return TransactionStatusResult(status: .pending, blockNumber: nil, confirmations: nil)
        }

        let blockNumber = first["block_number"] as? Int

        if let success = first["success"] as? Bool {
            if success {
                return TransactionStatusResult(
                    status: .confirmed,
                    blockNumber: blockNumber,
                    confirmations: nil
                )
            } else {
                return TransactionStatusResult(
                    status: .failed(reason: "Transaction failed on Bittensor network"),
                    blockNumber: blockNumber,
                    confirmations: nil
                )
            }
        }

        // If success field is missing, treat as pending
        return TransactionStatusResult(status: .pending, blockNumber: blockNumber, confirmations: nil)
    }
}
