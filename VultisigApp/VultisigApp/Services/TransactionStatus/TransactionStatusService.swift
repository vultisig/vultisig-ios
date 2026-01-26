//
//  TransactionStatusService.swift
//  VultisigApp
//
//  Created by Claude on 23/01/2025.
//

import Foundation

class TransactionStatusService {
    static let shared = TransactionStatusService()

    private let evmProvider = EVMTransactionStatusProvider()
    private let utxoProvider = UTXOTransactionStatusProvider()
    private let cosmosProvider = CosmosTransactionStatusProvider()
    private let solanaProvider = SolanaTransactionStatusProvider()

    private init() {}

    /// Check transaction status for any chain
    func checkTransactionStatus(txHash: String, chain: Chain) async throws -> TransactionStatusResult {
        let provider = getProvider(for: chain)
        return try await provider.checkStatus(txHash: txHash, chain: chain)
    }

    private func getProvider(for chain: Chain) -> TransactionStatusProvider {
        switch chain.chainType {
        case .EVM:
            return evmProvider
        case .UTXO:
            return utxoProvider
        case .Solana:
            return solanaProvider
        case .Cosmos, .THORChain:
            return cosmosProvider
        default:
            // Default to cosmos provider for other chains
            return cosmosProvider
        }
    }
}
