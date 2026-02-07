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
            return try await parseReceipt(receipt, service: service, txHash: query.txHash)
        }

        // No receipt — check if the transaction exists in the mempool
        return try await checkMempool(service: service, txHash: query.txHash)
    }

    // MARK: - Receipt Parsing

    private func parseReceipt(
        _ receipt: [String: Any],
        service: RpcEvmService,
        txHash: String
    ) async throws -> TransactionStatusResult {
        guard let status = receipt["status"] as? String else {
            // Old contracts without status field — assume success if receipt exists
            return TransactionStatusResult(status: .confirmed, blockNumber: nil, confirmations: nil)
        }

        let statusInt = BigInt(status.stripHexPrefix(), radix: 16) ?? BigInt.zero
        let txBlockNum = parseBlockNumber(receipt["blockNumber"] as? String)

        if statusInt == 1 {
            let confirmations = await getConfirmations(service: service, txBlockNumber: txBlockNum)
            return TransactionStatusResult(
                status: .confirmed,
                blockNumber: txBlockNum,
                confirmations: confirmations
            )
        }

        // Failed (reverted) — try to extract the revert reason
        let reason = await getRevertReason(service: service, txHash: txHash, blockNumber: receipt["blockNumber"] as? String)
        return TransactionStatusResult(
            status: .failed(reason: reason),
            blockNumber: txBlockNum,
            confirmations: nil
        )
    }

    // MARK: - Mempool Check

    /// Distinguish "pending in mempool" from "not found / dropped".
    private func checkMempool(service: RpcEvmService, txHash: String) async throws -> TransactionStatusResult {
        let tx = try await service.sendRPCRequest(
            method: "eth_getTransactionByHash",
            params: [txHash]
        ) { result in
            return result as? [String: Any]
        }

        if tx != nil {
            return TransactionStatusResult(status: .pending, blockNumber: nil, confirmations: nil)
        }

        return TransactionStatusResult(status: .notFound, blockNumber: nil, confirmations: nil)
    }

    // MARK: - Confirmations

    private func getConfirmations(service: RpcEvmService, txBlockNumber: Int?) async -> Int? {
        guard let txBlock = txBlockNumber else { return nil }

        do {
            let currentBlock = try await service.intRpcCall(method: "eth_blockNumber", params: [])
            let confirmations = Int(currentBlock) - txBlock
            return confirmations > 0 ? confirmations : nil
        } catch {
            return nil
        }
    }

    // MARK: - Revert Reason

    /// Replay a failed transaction with `eth_call` at the block it reverted
    /// to extract the revert reason from the RPC error.
    private func getRevertReason(service: RpcEvmService, txHash: String, blockNumber: String?) async -> String {
        do {
            let tx = try await service.sendRPCRequest(
                method: "eth_getTransactionByHash",
                params: [txHash]
            ) { result in
                return result as? [String: Any]
            }

            guard let tx,
                  let from = tx["from"] as? String,
                  let to = tx["to"] as? String,
                  let block = blockNumber else {
                return "Transaction reverted"
            }

            var callParams: [String: Any] = ["from": from, "to": to]

            if let value = tx["value"] as? String {
                callParams["value"] = value
            }
            if let data = tx["input"] as? String, data != "0x" {
                callParams["data"] = data
            }
            if let gas = tx["gas"] as? String {
                callParams["gas"] = gas
            }

            // eth_call will revert — the error message contains the reason
            _ = try await service.sendRPCRequest(
                method: "eth_call",
                params: [callParams, block]
            ) { result in
                return result as? String
            }

            return "Transaction reverted"
        } catch {
            return extractRevertReason(from: error.localizedDescription)
        }
    }

    /// Parse a human-readable revert reason from an RPC error string.
    private func extractRevertReason(from errorMessage: String) -> String {
        // Most RPC nodes return "execution reverted: <reason>"
        if let range = errorMessage.range(of: "execution reverted: ") {
            let reason = String(errorMessage[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !reason.isEmpty {
                return reason
            }
        }
        if errorMessage.lowercased().contains("execution reverted") {
            return "Transaction reverted"
        }
        return "Transaction reverted"
    }

    // MARK: - Helpers

    private func parseBlockNumber(_ hex: String?) -> Int? {
        hex.flatMap { Int(BigInt($0.stripHexPrefix(), radix: 16) ?? BigInt.zero) }
    }
}
