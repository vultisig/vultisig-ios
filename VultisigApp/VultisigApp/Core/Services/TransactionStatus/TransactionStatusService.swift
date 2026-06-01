//
//  TransactionStatusService.swift
//  VultisigApp
//
//  Created by Claude on 23/01/2025.
//

import Foundation

/// Seam for the transaction-status lookup so callers can be tested with a
/// fake that returns `.confirmed` / `.notFound` / throws without touching the
/// network. `TransactionStatusService.shared` is the production conformer.
protocol TransactionStatusChecking: Sendable {
    func checkTransactionStatus(txHash: String, chain: Chain) async throws -> TransactionStatusResult
}

final class TransactionStatusService: TransactionStatusChecking, @unchecked Sendable {
    static let shared = TransactionStatusService()

    private let evmProvider = EVMTransactionStatusProvider()
    private let utxoProvider = UTXOTransactionStatusProvider()
    private let cosmosProvider = CosmosTransactionStatusProvider()
    private let solanaProvider = SolanaTransactionStatusProvider()
    private let thorchainProvider = THORChainTransactionStatusProvider()
    private let cardanoProvider = CardanoTransactionStatusProvider()
    private let polkadotProvider = PolkadotTransactionStatusProvider()
    private let bittensorProvider = BittensorTransactionStatusProvider()
    private let suiProvider = SuiTransactionStatusProvider()
    private let tonProvider = TonTransactionStatusProvider()
    private let rippleProvider = RippleTransactionStatusProvider()
    private let tronProvider = TronTransactionStatusProvider()

    private init() {}

    /// Check transaction status for any chain
    func checkTransactionStatus(txHash: String, chain: Chain) async throws -> TransactionStatusResult {
        let query = TransactionStatusQuery(txHash: txHash, chain: chain)
        let provider = getProvider(for: chain)
        return try await provider.checkStatus(query: query)
    }

    private func getProvider(for chain: Chain) -> TransactionStatusProvider {
        // Chain-specific overrides (same chainType, different provider)
        if chain == .bittensor {
            return bittensorProvider
        }

        switch chain.chainType {
        case .EVM:
            return evmProvider
        case .UTXO:
            return utxoProvider
        case .Solana:
            return solanaProvider
        case .Cosmos:
            return cosmosProvider
        case .THORChain:
            return thorchainProvider
        case .Cardano:
            return cardanoProvider
        case .Polkadot:
            return polkadotProvider
        case .Sui:
            return suiProvider
        case .Ton:
            return tonProvider
        case .Ripple:
            return rippleProvider
        case .Tron:
            return tronProvider
        }
    }
}
