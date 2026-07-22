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

    /// Get all supported chains grouped by feature type
    /// - Returns: Dictionary mapping feature types to supported chains
    func getSupportedChains() -> [SecurityScannerFeaturesType: [Chain]]

}
