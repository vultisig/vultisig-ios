//
//  BlockaidScannerService.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 29/07/2025.
//

import Foundation
import BigInt
import OSLog

class BlockaidScannerService: BlockaidScannerServiceProtocol {

    private let blockaidRpcClient: BlockaidRpcClientProtocol
    private let logger = Logger(subsystem: "com.vultisig.app", category: "blockaid-scanner")

    init(blockaidRpcClient: BlockaidRpcClientProtocol) {
        self.blockaidRpcClient = blockaidRpcClient
    }

    func scanTransaction(_ transaction: SecurityScannerTransaction) async throws -> SecurityScannerResult {
        let chain = transaction.chain

        switch chain {
        case .arbitrum, .avalanche, .base, .blast, .bscChain, .ethereum, .optimism, .polygon, .polygonV2:
            return try await scanEvmTransaction(transaction)
        case .bitcoin:
            return try await scanBitcoinTransaction(transaction)
        case .solana:
            return try await scanSolanaTransaction(transaction)
        case .sui:
            return try await scanSuiTransaction(transaction)
        default:
            throw BlockaidScannerError.scannerError("Chain \(chain) is not supported", payload: nil)
        }
    }

    func getProviderName() -> String {
        return Constants.providerName
    }

    func supportsChain(_ chain: Chain, feature: SecurityScannerFeaturesType) -> Bool {
        guard let supportedChainsByFeature = getSupportedChains()[feature] else {
            return false
        }

        return supportedChainsByFeature.contains(chain)
    }

    func getSupportedChains() -> [SecurityScannerFeaturesType: [Chain]] {
        return [
            .scanTransaction: Constants.supportedChains
        ]
    }

    func getSupportedFeatures() -> [SecurityScannerFeaturesType] {
        return [.scanTransaction]
    }
}

// MARK: - Private Scan Methods

private extension BlockaidScannerService {

    func scanEvmTransaction(_ transaction: SecurityScannerTransaction) async throws -> SecurityScannerResult {
        return try await runSecurityScan(transaction) {
            let response = try await blockaidRpcClient.scanEVMTransaction(
                chain: transaction.chain,
                from: transaction.from,
                to: transaction.to,
                amount: transaction.amount.toHexString(),
                data: transaction.data
            )
            return try response.toSecurityScannerResult(provider: Constants.providerName)
        }
    }

    func scanBitcoinTransaction(_ transaction: SecurityScannerTransaction) async throws -> SecurityScannerResult {
        return try await runSecurityScan(transaction) {
            let response = try await blockaidRpcClient.scanBitcoinTransaction(
                address: transaction.from,
                serializedTransaction: transaction.data
            )
            return try response.toSecurityScannerResult(provider: Constants.providerName)
        }
    }

    func scanSolanaTransaction(_ transaction: SecurityScannerTransaction) async throws -> SecurityScannerResult {
        return try await runSecurityScan(transaction) {
            let response = try await blockaidRpcClient.scanSolanaTransaction(
                address: transaction.from,
                serializedMessage: transaction.data
            )
            return try response.toSolanaSecurityScannerResult(provider: Constants.providerName)
        }
    }

    func scanSuiTransaction(_ transaction: SecurityScannerTransaction) async throws -> SecurityScannerResult {
        return try await runSecurityScan(transaction) {
            let response = try await blockaidRpcClient.scanSuiTransaction(
                address: transaction.from,
                serializedTransaction: transaction.data
            )
            return try response.toSecurityScannerResult(provider: Constants.providerName)
        }
    }

    /// Runs security scan with error handling and logging
    func runSecurityScan(
        _ transaction: SecurityScannerTransaction,
        operation: () async throws -> SecurityScannerResult
    ) async throws -> SecurityScannerResult {
        logger.info("🔍 Starting security scan for \(transaction.chain.name) transaction")

        do {
            let result = try await operation()
            logger.info("✅ Security scan completed - Result: \(result.riskLevel.rawValue)")
            return result
        } catch {
            logger.error("❌ Security scan failed: \(error.localizedDescription)")
            throw error
        }
    }
}

// MARK: - Constants

private extension BlockaidScannerService {
    enum Constants {
        static let supportedChains: [Chain] = [
            .arbitrum,
            .avalanche,
            .base,
            .blast,
            .bscChain,
            .ethereum,
            .optimism,
            .polygon,
            .polygonV2,
            .sui,
            .solana,
            .bitcoin
        ]

        static let providerName = "blockaid"
    }
}

// MARK: - BigInt Extension

extension BigInt {
    func toHexString() -> String {
        return "0x" + String(self, radix: 16)
    }

    func toEvenLengthHexString() -> String {
            var hex = self.toHexString()
            if hex.hasPrefix("0x") {
                hex = String(hex.dropFirst(2))
            }
            if hex.count % 2 != 0 {
                hex = "0" + hex
            }
            return "0x" + hex
        }
}
