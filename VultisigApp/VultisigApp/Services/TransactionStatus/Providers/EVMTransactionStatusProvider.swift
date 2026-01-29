//
//  EVMTransactionStatusProvider.swift
//  VultisigApp
//
//  Created by Claude on 23/01/2025.
//

import Foundation
import BigInt

struct EVMTransactionStatusProvider: TransactionStatusProvider {

    func checkStatus(query: TransactionStatusQuery) async throws -> TransactionStatusResult {
        let config = try EvmServiceConfig.getConfig(forChain: query.chain)
        let service = RpcEvmService(config.rpcEndpoint)

        // Call eth_getTransactionReceipt
        let receipt = try await service.sendRPCRequest(
            method: "eth_getTransactionReceipt",
            params: [query.txHash]
        ) { result in
            return result as? [String: Any]
        }

        if let receipt = receipt {
            // Receipt exists = confirmed
            // Check status field (1 = success, 0 = failed)
            if let status = receipt["status"] as? String {
                let statusInt = BigInt(status.stripHexPrefix(), radix: 16) ?? BigInt.zero

                if statusInt == 1 {
                    // Success
                    let blockNumber = receipt["blockNumber"] as? String
                    let blockNum = blockNumber.flatMap { Int(BigInt($0.stripHexPrefix(), radix: 16) ?? BigInt.zero) }

                    return TransactionStatusResult(
                        status: .confirmed,
                        blockNumber: blockNum,
                        confirmations: nil
                    )
                } else {
                    // Failed (reverted)
                    return TransactionStatusResult(
                        status: .failed(reason: "Transaction reverted"),
                        blockNumber: nil,
                        confirmations: nil
                    )
                }
            }

            // Old contracts without status field - assume success if receipt exists
            return TransactionStatusResult(
                status: .confirmed,
                blockNumber: nil,
                confirmations: nil
            )
        }

        // No receipt = still pending or not found
        return TransactionStatusResult(
            status: .pending,
            blockNumber: nil,
            confirmations: nil
        )
    }
}
