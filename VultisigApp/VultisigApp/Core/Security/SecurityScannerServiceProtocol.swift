//
//  SecurityScannerServiceProtocol.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 29/07/2025.
//

import Foundation

// MARK: - SecurityScannerServiceProtocol

protocol SecurityScannerServiceProtocol {
    /// Scan a transaction for security issues using enabled providers
    /// - Parameter transaction: The transaction to scan
    /// - Returns: Security scan result from the first available provider
    func scanTransaction(_ transaction: SecurityScannerTransaction) async throws -> SecurityScannerResult

    /// Check if security scanning service is enabled
    /// - Returns: true if service is enabled, false otherwise
    func isSecurityServiceEnabled() -> Bool

    /// Create SecurityScannerTransaction from a regular transaction
    /// - Parameter transaction: The transaction to convert
    /// - Returns: SecurityScannerTransaction ready for scanning
    func createSecurityScannerTransaction(transaction: SendTransaction, vault: Vault) async throws -> SecurityScannerTransaction

    /// Create SecurityScannerTransaction from a swap transaction
    /// - Parameter transaction: The swap transaction to convert
    /// - Returns: SecurityScannerTransaction ready for scanning
    func createSecurityScannerTransaction(transaction: SwapTransaction) async throws -> SecurityScannerTransaction

    /// Get list of disabled provider names
    /// - Returns: Array of disabled provider names
    func getDisabledProviders() -> [String]

    /// Get list of enabled provider names
    /// - Returns: Array of enabled provider names
    func getEnabledProviders() -> [String]

    /// Disable specific security providers
    /// - Parameter providersToDisable: Array of provider names to disable
    func disableProviders(_ providersToDisable: [String])

    /// Enable specific security providers
    /// - Parameter providersToEnable: Array of provider names to enable
    func enableProviders(_ providersToEnable: [String])

    /// Get supported chains by feature for all providers
    /// - Returns: Array of SecurityScannerSupport objects
    func getSupportedChainsByFeature() -> [SecurityScannerSupport]
}

/// Protocol for security scanner transaction factory
protocol SecurityScannerTransactionFactoryProtocol {
    /// Create SecurityScannerTransaction from a regular transaction
    /// - Parameters:
    ///   - transaction: The transaction to convert
    ///   - vault: The vault containing transaction details
    /// - Returns: SecurityScannerTransaction ready for scanning
    func createSecurityScanner(transaction: SendTransaction, vault: Vault) async throws -> SecurityScannerTransaction

    /// Create SecurityScannerTransaction from a swap transaction
    /// - Parameter transaction: The swap transaction to convert
    /// - Returns: SecurityScannerTransaction ready for scanning
    func createSecurityScanner(transaction: SwapTransaction) async throws -> SecurityScannerTransaction
}
