//
//  BlockaidExtensions.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 29/07/2025.
//

import Foundation
import OSLog

// MARK: - SecurityScannerError

enum BlockaidScannerError: Error, LocalizedError {
    case scannerError(String, payload: String?)
    case invalidResponse(String, payload: String?)

    var errorDescription: String? {
        switch self {
        case .scannerError(let message, _):
            return "SecurityScanner Error: \(message)"
        case .invalidResponse(let message, _):
            return "SecurityScanner Invalid response: \(message)"
        }
    }
}

// MARK: - BlockaidTransactionScanResponseJson Extensions

extension BlockaidTransactionScanResponseJson {

    // Solana has different payload, for simplicity, avoid confusion and any potential bug
    // we'll keep it separated. Other chains such as SUI and BTC shared the same EVM payload
    func toSolanaSecurityScannerResult(provider: String) throws -> SecurityScannerResult {
        // Check for errors first
        if status?.lowercased() == "error" || error != nil {
            let errorMessage = error ?? "Unknown error"
            throw BlockaidScannerError.scannerError(errorMessage, payload: "\(self)")
        }

        guard let result = result else {
            throw BlockaidScannerError.invalidResponse("'result' is null", payload: "\(self)")
        }

        let riskLevel = result.validation.toSolanaValidationRiskLevel()
        let isSecure = riskLevel == .none || riskLevel == .low

        var description: String?
        if isSecure {
            description = result.validation.features.prefix(3).joined(separator: "\n")
        }

        let warnings = result.validation.extendedFeatures.map { extendedFeature in
            SecurityWarning(
                type: extendedFeature.type.toWarningType(),
                severity: "",
                message: extendedFeature.description,
                details: nil
            )
        }

        return SecurityScannerResult(
            provider: provider,
            isSecure: isSecure,
            riskLevel: riskLevel,
            warnings: warnings,
            description: description,
            recommendations: "",
            metadata: SecurityScannerMetadata()
        )
    }

    func toSecurityScannerResult(provider: String) throws -> SecurityScannerResult {
        let riskLevel = try toValidationRiskLevel()

        let securityWarnings = validation?.features?.map { feature in
            SecurityWarning(
                type: feature.type.toWarningType(),
                severity: feature.featureId,
                message: feature.description,
                details: feature.address
            )
        } ?? []

        let recommendations = validation?.classification?.toRecommendations() ?? ""
        let isSecure = riskLevel == .none || riskLevel == .low

        return SecurityScannerResult(
            provider: provider,
            isSecure: isSecure,
            riskLevel: riskLevel,
            warnings: securityWarnings,
            description: validation?.description,
            recommendations: recommendations,
            metadata: SecurityScannerMetadata(
                requestId: requestId ?? "",
                classification: validation?.classification ?? "",
                resultType: validation?.resultType ?? ""
            )
        )
    }
}

// MARK: - Private Extensions

private extension BlockaidTransactionScanResponseJson.BlockaidSolanaResultJson.BlockaidSolanaValidationJson {

    func toSolanaValidationRiskLevel() -> SecurityRiskLevel {
        let isBenign = resultType.lowercased() == "benign" && features.isEmpty

        if isBenign {
            return .none
        }

        return resultType.toWarningType()
    }
}

private extension BlockaidTransactionScanResponseJson {

    func toValidationRiskLevel() throws -> SecurityRiskLevel {
        let hasFeatures = validation?.features?.isEmpty == false
        let classification = validation?.classification
        let validationStatus = validation?.status
        let globalStatus = status
        let resultType = validation?.resultType

        // Check for error conditions
        if validationStatus?.lowercased() == "error" ||
           resultType?.lowercased() == "error" ||
           globalStatus?.lowercased() == "error" {
            let errorMessage = validation?.error ?? "Scanning failed"
            throw BlockaidScannerError.scannerError(errorMessage, payload: "\(self)")
        }

        // Check if benign
        let isBenign = validationStatus?.lowercased() == "success" &&
                      resultType?.lowercased() == "benign" &&
                      !hasFeatures

        if isBenign {
            return .none
        }

        let label = resultType ?? classification
        return label?.toWarningType() ?? .medium
    }
}

// MARK: - String Extensions

private extension String {

    func toWarningType() -> SecurityRiskLevel {
        let logger = Logger(subsystem: "com.vultisig.app", category: "security-scanner")

        switch self.lowercased() {
        case "benign", "info":
            return .low
        case "warning", "spam":
            return .medium
        case "malicious":
            return .critical
        default:
            logger.warning("SecurityScanner: Unknown risk classification: \(self)")
            return .medium
        }
    }
}

private extension String {

    func toRecommendations() -> String {
        switch self.lowercased() {
        case "malicious":
            return "This transaction is flagged as malicious. Do not proceed."
        case "warning":
            return "This transaction has been flagged with warnings. Review carefully before proceeding."
        case "spam":
            return "This transaction appears to be spam. Consider avoiding it."
        default:
            return ""
        }
    }
}
