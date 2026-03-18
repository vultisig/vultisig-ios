//
//  BlockaidScannerServiceProtocol.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 29/07/2025.
//

import Foundation

protocol BlockaidScannerServiceProtocol {
    /// Scan a transaction for security issues
    /// - Parameter transaction: The transaction details to scan
    /// - Returns: Security scan result with warnings and recommendations
    func scanTransaction(_ transaction: SecurityScannerTransaction) async throws -> SecurityScannerResult

    /// Get the provider name
    /// - Returns: The name of this security provider
    func getProviderName() -> String

    /// Check if this provider supports the given chain for a specific feature
    /// - Parameters:
    ///   - chain: The blockchain chain to check
    ///   - feature: The security scanner feature type
    /// - Returns: true if the chain and feature combination is supported
    func supportsChain(_ chain: Chain, feature: SecurityScannerFeaturesType) -> Bool

    /// Get all supported chains grouped by feature type
    /// - Returns: Dictionary mapping feature types to supported chains
    func getSupportedChains() -> [SecurityScannerFeaturesType: [Chain]]

    /// Get all supported security scanner features
    /// - Returns: List of supported feature types
    func getSupportedFeatures() -> [SecurityScannerFeaturesType]
}
