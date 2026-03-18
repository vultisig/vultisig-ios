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
    private let thorchainProvider = THORChainTransactionStatusProvider()
    private let cardanoProvider = CardanoTransactionStatusProvider()
    private let polkadotProvider = PolkadotTransactionStatusProvider()
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
