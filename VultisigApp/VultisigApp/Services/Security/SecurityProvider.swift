//
//  SecurityProvider.swift
//  VultisigApp
//
//  Created by Assistant on 2025-01-14.
//

import Foundation
import BigInt

// MARK: - Core Protocol

/// Protocol for security/fraud detection providers
protocol SecurityProvider {
    /// The name of the security provider (e.g., "Blockaid", "Blowfish")
    var providerName: String { get }
    
    /// Scan a transaction for security issues
    /// - Parameters:
    ///   - request: The security scan request containing transaction details
    /// - Returns: A security scan response with warnings and recommendations
    func scanTransaction(_ request: SecurityScanRequest) async throws -> SecurityScanResponse
    
    /// Check if this provider supports the given chain
    /// - Parameter chain: The blockchain chain to check
    /// - Returns: true if the chain is supported, false otherwise
    func supportsChain(_ chain: Chain) -> Bool
}

// MARK: - Request/Response Models

/// Request model for security scanning
struct SecurityScanRequest {
    let chain: Chain
    let transactionType: SecurityTransactionType
    let fromAddress: String
    let toAddress: String
    let amount: String?
    let data: String?
    let metadata: [String: Any]?
    
    init(chain: Chain,
         transactionType: SecurityTransactionType,
         fromAddress: String,
         toAddress: String,
         amount: String? = nil,
         data: String? = nil,
         metadata: [String: Any]? = nil) {
        self.chain = chain
        self.transactionType = transactionType
        self.fromAddress = fromAddress
        self.toAddress = toAddress
        self.amount = amount
        self.data = data
        self.metadata = metadata
    }
}

/// Response model for security scanning
struct SecurityScanResponse {
    let provider: String
    let isSecure: Bool
    let riskLevel: SecurityRiskLevel
    let warnings: [SecurityWarning]
    let recommendations: [String]
    let metadata: [String: Any]?
    
    /// Convenience property to check if there are any warnings
    var hasWarnings: Bool {
        return !warnings.isEmpty
    }
    
    /// Get all warning messages as strings
    var warningMessages: [String] {
        return warnings.map { $0.message }
    }
}

/// Individual security warning
struct SecurityWarning2 {
    let type: SecurityWarningType
    let severity: SecuritySeverity
    let message: String
    let details: String?
    
    init(type: SecurityWarningType, severity: SecuritySeverity, message: String, details: String? = nil) {
        self.type = type
        self.severity = severity
        self.message = message
        self.details = details
    }
}

// MARK: - Enums

/// Types of security transactions
enum SecurityTransactionType2 {
    case transfer
    case swap
    case contractInteraction
    case tokenApproval
    case nftTransfer
    case defiInteraction
    case other(String)
}

/// Security risk levels
enum SecurityRiskLevel2: String, CaseIterable {
    case none = "NONE"
    case low = "LOW"
    case medium = "MEDIUM"
    case high = "HIGH"
    case critical = "CRITICAL"
    
    var displayName: String {
        switch self {
        case .none: return "Secure"
        case .low: return "Low Risk"
        case .medium: return "Medium Risk"
        case .high: return "High Risk"
        case .critical: return "Critical Risk"
        }
    }
}

/// Security warning types
enum SecurityWarningType: String, CaseIterable {
    case suspiciousContract = "SUSPICIOUS_CONTRACT"
    case highValueTransfer = "HIGH_VALUE_TRANSFER"
    case unknownToken = "UNKNOWN_TOKEN"
    case phishingAttempt = "PHISHING_ATTEMPT"
    case maliciousContract = "MALICIOUS_CONTRACT"
    case unusualActivity = "UNUSUAL_ACTIVITY"
    case rugPullRisk = "RUG_PULL_RISK"
    case sandwichAttack = "SANDWICH_ATTACK"
    case frontRunning = "FRONT_RUNNING"
    case other = "OTHER"
}

/// Security warning severity levels
enum SecuritySeverity: String, CaseIterable {
    case info = "INFO"
    case warning = "WARNING"
    case error = "ERROR"
    case critical = "CRITICAL"
    
    var displayName: String {
        switch self {
        case .info: return "Info"
        case .warning: return "Warning"
        case .error: return "Error"
        case .critical: return "Critical"
        }
    }
}

// MARK: - Error Types

enum SecurityProviderError: Error, LocalizedError {
    case providerNotSupported(String)
    case chainNotSupported(Chain)
    case networkError(String)
    case apiError(String)
    case invalidRequest(String)
    case rateLimitExceeded
    case unauthorized
    case unsupportedOperation(String)
    
    var errorDescription: String? {
        switch self {
        case .providerNotSupported(let provider):
            return "Security provider '\(provider)' is not supported"
        case .chainNotSupported(let chain):
            return "Chain '\(chain.name)' is not supported by the security provider"
        case .networkError(let message):
            return "Network error: \(message)"
        case .apiError(let message):
            return "API error: \(message)"
        case .invalidRequest(let message):
            return "Invalid request: \(message)"
        case .rateLimitExceeded:
            return "Rate limit exceeded. Please try again later."
        case .unauthorized:
            return "Unauthorized access to security provider"
        case .unsupportedOperation(let message):
            return "Operation not supported: \(message)"
        }
    }
}
