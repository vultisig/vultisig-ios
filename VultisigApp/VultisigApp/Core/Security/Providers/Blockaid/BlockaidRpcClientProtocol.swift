//
//  BlockaidRpcClientProtocol.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 29/07/2025.
//

import Foundation

protocol BlockaidRpcClientProtocol {
    func scanBitcoinTransaction(
        address: String,
        serializedTransaction: String
    ) async throws -> BlockaidTransactionScanResponseJson

    func scanEVMTransaction(
        chain: Chain,
        from: String,
        to: String,
        amount: String,
        data: String
    ) async throws -> BlockaidTransactionScanResponseJson

    func simulateEVMTransaction(
        chain: Chain,
        from: String,
        to: String,
        amount: String,
        data: String
    ) async throws -> BlockaidEvmSimulationResponseJson

    func scanSolanaTransaction(
        address: String,
        serializedMessage: String
    ) async throws -> BlockaidTransactionScanResponseJson

    func simulateSolanaTransaction(
        address: String,
        rawTransactions: [String]
    ) async throws -> BlockaidSolanaSimulationResponseJson

    func scanSuiTransaction(
        address: String,
        serializedTransaction: String
    ) async throws -> BlockaidTransactionScanResponseJson
}
