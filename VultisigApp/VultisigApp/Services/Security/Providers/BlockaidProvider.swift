//
//  BlockaidProvider.swift
//  VultisigApp
//
//  Created by Assistant on 2025-01-14.
//

import Foundation
import BigInt
import OSLog

/// Blockaid security provider implementation
class BlockaidProvider: CapabilityAwareSecurityProvider {
    
    private let logger = Logger(subsystem: "blockaid-provider", category: "security")
    private let baseURL = Endpoint.blockaidApiBase
    private let session = URLSession.shared
    
    // MARK: - CapabilityAwareSecurityProvider
    let capabilities: SecurityProviderCapabilities
    
    init(capabilities: SecurityProviderCapabilities = .blockaid) {
        self.capabilities = capabilities
        // API key is handled by the Vultisig proxy
    }
    
    // MARK: - SecurityProvider Protocol
    
    var providerName: String {
        return "Blockaid"
    }
    
    func supportsChain(_ chain: Chain) -> Bool {
        switch chain.chainType {
        case .EVM:
            return capabilities.evmTransactionScanning
        case .Solana:
            return capabilities.solanaTransactionScanning
        case .UTXO:
            return capabilities.bitcoinTransactionScanning
        case .Cosmos:
            return false // Blockaid doesn't support Cosmos chains yet
        default:
            // Check for specific chain support
            switch chain {
            case .bitcoin, .bitcoinCash, .litecoin, .dogecoin, .dash:
                return capabilities.bitcoinTransactionScanning
            case .solana:
                return capabilities.solanaTransactionScanning
            default:
                return false
            }
        }
    }
    
    func scanTransaction(_ request: SecurityScanRequest) async throws -> SecurityScanResponse {
        switch request.chain.chainType {
        case .EVM:
            return try await scanEVMTransaction(request)
        case .Solana:
            // Solana scanning - using existing endpoint
            return try await scanSolanaTransaction(request)
        case .UTXO:
            // Bitcoin scanning - using existing endpoint  
            return try await scanBitcoinTransaction(request)
        default:
            // For other chains, try EVM scanning as fallback
            return try await scanEVMTransaction(request)
        }
    }
    
    func validateAddress(_ address: String, for chain: Chain) async throws -> SecurityScanResponse {
        switch chain.chainType {
        case .EVM:
            return try await scanEVMAddress(address, for: chain)
        case .Solana:
            return try await scanSolanaAddress(address, for: chain)
        default:
            throw SecurityProviderError.unsupportedOperation("Address validation not supported for chain: \(chain.name)")
        }
    }
    
    func scanSite(_ url: String) async throws -> SecurityScanResponse {
        let endpoint = Endpoint.blockaidSiteScan()
        
        guard let requestURL = URL(string: endpoint) else {
            throw SecurityProviderError.invalidRequest("Invalid URL")
        }
        
        let requestBody = BlockaidSiteScanRequest(
            url: url,
            metadata: BlockaidRequestMetadata(domain: "vultisig.com")
        )
        
        do {
            let response: BlockaidTransactionScanResponse = try await performRequest(url: requestURL, body: requestBody)
            return mapTransactionScanResponseToSecurityResponse(response)
        } catch {
            logger.error("Site scan failed: \(error)")
            throw error
        }
    }
    
    func scanToken(_ tokenAddress: String, for chain: Chain) async throws -> SecurityScanResponse {
        let endpoint = Endpoint.blockaidTokenScan()
        
        guard let url = URL(string: endpoint) else {
            throw SecurityProviderError.invalidRequest("Invalid URL")
        }
        
        let requestBody = BlockaidTokenScanRequest(
            chain: mapChainToBlockaidChain(chain),
            address: tokenAddress,
            metadata: BlockaidRequestMetadata(domain: "vultisig.com")
        )
        
        do {
            let response: BlockaidTransactionScanResponse = try await performRequest(url: url, body: requestBody)
            return mapTransactionScanResponseToSecurityResponse(response)
        } catch {
            logger.error("Token scan failed: \(error)")
            throw error
        }
    }
    
    // MARK: - EVM Scanning
    
    private func scanEVMTransaction(_ request: SecurityScanRequest) async throws -> SecurityScanResponse {
        let endpoint = Endpoint.blockaidEVMJSONRPCScan()
        
        guard let url = URL(string: endpoint) else {
            throw SecurityProviderError.invalidRequest("Invalid URL")
        }
        
        let requestBody = BlockaidEVMRequest(
            chain: mapChainToBlockaidChain(request.chain),
            data: BlockaidEVMJSONRPCData(
                method: "eth_sendTransaction",
                params: [[
                    "from": request.fromAddress,
                    "to": request.toAddress,
                    "value": convertAmountToHex(request.amount),
                    "data": request.data ?? "0x"
                ]]
            ),
            metadata: BlockaidRequestMetadata(
                domain: "vultisig.com"
            )
        )
        
        do {
            let response: BlockaidTransactionScanResponse = try await performRequest(url: url, body: requestBody)
            return mapTransactionScanResponseToSecurityResponse(response)
        } catch {
            logger.error("EVM transaction scan failed: \(error)")
            throw error
        }
    }
    
    private func scanEVMAddress(_ address: String, for chain: Chain) async throws -> SecurityScanResponse {
        let endpoint = Endpoint.blockaidEVMAddressScan()
        
        guard let url = URL(string: endpoint) else {
            throw SecurityProviderError.invalidRequest("Invalid URL")
        }
        
        let requestBody = BlockaidAddressScanRequest(
            chain: mapChainToBlockaidChain(chain),
            address: address,
            metadata: BlockaidRequestMetadata(domain: "vultisig.com")
        )
        
        do {
            let response: BlockaidTransactionScanResponse = try await performRequest(url: url, body: requestBody)
            return mapTransactionScanResponseToSecurityResponse(response)
        } catch {
            logger.error("EVM address scan failed: \(error)")
            throw error
        }
    }
    
    // MARK: - Bitcoin Scanning
    
    private func scanBitcoinTransaction(_ request: SecurityScanRequest) async throws -> SecurityScanResponse {
        let endpoint = Endpoint.blockaidBitcoinTransactionRaw()
        
        guard let url = URL(string: endpoint) else {
            throw SecurityProviderError.invalidRequest("Invalid URL")
        }
        
        let requestBody = BlockaidBitcoinRequest(
            chain: mapChainToBlockaidChain(request.chain),
            data: BlockaidBitcoinTransactionData(
                rawTransaction: request.data ?? "",
                fromAddress: request.fromAddress,
                toAddress: request.toAddress,
                amount: request.amount ?? "0"
            ),
            metadata: BlockaidRequestMetadata(
                domain: "vultisig.com"
            )
        )
        
        do {
            let response: BlockaidTransactionScanResponse = try await performRequest(url: url, body: requestBody)
            return mapTransactionScanResponseToSecurityResponse(response)
        } catch {
            logger.error("Bitcoin transaction scan failed: \(error)")
            throw error
        }
    }
    
    // MARK: - Solana Scanning
    
    private func scanSolanaTransaction(_ request: SecurityScanRequest) async throws -> SecurityScanResponse {
        let endpoint = Endpoint.blockaidSolanaMessageScan()
        
        guard let url = URL(string: endpoint) else {
            throw SecurityProviderError.invalidRequest("Invalid URL")
        }
        
        // Log the incoming request data
        logger.info("🚀 SOLANA SECURITY SCAN REQUEST:")
        logger.info("   - From Address: \(request.fromAddress)")
        logger.info("   - To Address: \(request.toAddress)")
        logger.info("   - Amount: \(request.amount ?? "nil")")
        logger.info("   - Data: \(request.data ?? "nil")")
        logger.info("   - Data Length: \((request.data ?? "").count) characters")
        
        // If data is base64, try to decode it
        if let data = request.data, let decodedData = Data(base64Encoded: data) {
            logger.info("   - Decoded Data (hex): \(decodedData.hexString)")
            logger.info("   - Decoded Data Length: \(decodedData.count) bytes")
        }
        
        let requestBody = BlockaidSolanaRequest(
            chain: "solana",
            data: BlockaidSolanaMessageData(
                message: request.data ?? "",
                accountAddress: request.fromAddress
            ),
            metadata: BlockaidRequestMetadata(
                domain: "vultisig.com"
            )
        )
        
        do {
            let response: BlockaidTransactionScanResponse = try await performRequest(url: url, body: requestBody)
            return mapTransactionScanResponseToSecurityResponse(response)
        } catch {
            logger.error("Solana transaction scan failed: \(error)")
            throw error
        }
    }
    
    private func scanSolanaAddress(_ address: String, for chain: Chain) async throws -> SecurityScanResponse {
        let endpoint = Endpoint.blockaidSolanaAddressScan()
        
        guard let url = URL(string: endpoint) else {
            throw SecurityProviderError.invalidRequest("Invalid URL")
        }
        
        let requestBody = BlockaidAddressScanRequest(
            chain: "solana",
            address: address,
            metadata: BlockaidRequestMetadata(domain: "vultisig.com")
        )
        
        do {
            let response: BlockaidTransactionScanResponse = try await performRequest(url: url, body: requestBody)
            return mapTransactionScanResponseToSecurityResponse(response)
        } catch {
            logger.error("Solana address scan failed: \(error)")
            throw error
        }
    }
    
    // MARK: - HTTP Request Handling
    
    private func performRequest<T: Codable, R: Codable>(url: URL, body: T) async throws -> R {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // API key authentication is handled by the Vultisig proxy
        
        do {
            let requestData = try JSONEncoder().encode(body)
            request.httpBody = requestData
            
            // Log the request being sent
            if let requestString = String(data: requestData, encoding: .utf8) {
                logger.info("📤 BLOCKAID API REQUEST to \(url.absoluteString):")
                logger.info("\(requestString)")
            }
            
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw SecurityProviderError.networkError("Invalid response type")
            }
            
            switch httpResponse.statusCode {
            case 200...299:
                // Log the raw API response
                if let responseString = String(data: data, encoding: .utf8) {
                    logger.info("🌐 BLOCKAID RAW API RESPONSE:")
                    logger.info("\(responseString)")
                } else {
                    logger.info("🌐 BLOCKAID RAW API RESPONSE: [Unable to decode response as UTF-8 string]")
                }
                
                let decoder = JSONDecoder()
                // Don't use convertFromSnakeCase as it conflicts with explicit CodingKeys
                return try decoder.decode(R.self, from: data)
            case 401:
                throw SecurityProviderError.unauthorized
            case 429:
                throw SecurityProviderError.rateLimitExceeded
            default:
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw SecurityProviderError.apiError("HTTP \(httpResponse.statusCode): \(errorMessage)")
            }
        } catch {
            if error is SecurityProviderError {
                throw error
            }
            throw SecurityProviderError.networkError(error.localizedDescription)
        }
    }
    
    // MARK: - Response Mapping
    
    private func mapTransactionScanResponseToSecurityResponse(_ response: BlockaidTransactionScanResponse) -> SecurityScanResponse {
        // Debug logging - print the full Blockaid response
        logger.info("🔍 BLOCKAID RESPONSE DEBUG:")
        logger.info("📋 Request ID: \(response.requestId ?? "nil")")
        logger.info("✅ Status: \(response.validation?.status ?? "nil")")
        logger.info("🏷️ Classification: \(response.validation?.classification ?? "nil")")
        logger.info("🔍 Result Type: \(response.validation?.resultType ?? "nil")")
        
        if let features = response.validation?.features, !features.isEmpty {
            logger.info("⚠️ Features found (\(features.count)):")
            for (index, feature) in features.enumerated() {
                logger.info("   Feature \(index + 1):")
                logger.info("     - Type: \(feature.type)")
                logger.info("     - Severity: \(feature.severity ?? "nil")")
                logger.info("     - Description: \(feature.description)")
                logger.info("     - Address: \(feature.address ?? "nil")")
            }
        } else {
            logger.info("✅ No features/warnings detected")
        }
        
        let hasFeatures = response.validation?.features?.isEmpty == false
        let riskLevel = mapBlockaidValidationToRiskLevel(
            response.validation?.classification, 
            resultType: response.validation?.resultType,
            status: response.validation?.status,
            hasFeatures: hasFeatures
        )
        logger.info("🎯 Mapped Risk Level: \(riskLevel.rawValue)")
        
        let warnings = response.validation?.features?.compactMap { feature in
            SecurityWarning(
                type: mapBlockaidFeatureToWarningType(feature.type),
                severity: mapBlockaidSeverityToSecuritySeverity(feature.severity ?? "medium"),
                message: feature.description,
                details: feature.address
            )
        } ?? []
        
        var recommendations: [String] = []
        if let classification = response.validation?.classification {
            switch classification.lowercased() {
            case "malicious":
                recommendations.append("⚠️ This transaction is flagged as malicious. Do not proceed.")
            case "warning":
                recommendations.append("⚠️ This transaction has been flagged with warnings. Review carefully before proceeding.")
            case "spam":
                recommendations.append("This transaction appears to be spam. Consider avoiding it.")
            default:
                break
            }
        }
        
        return SecurityScanResponse(
            provider: providerName,
            isSecure: riskLevel == .none || riskLevel == .low,
            riskLevel: riskLevel,
            warnings: warnings,
            recommendations: recommendations,
            metadata: [
                "requestId": response.requestId ?? "",
                "classification": response.validation?.classification ?? "",
                "resultType": response.validation?.resultType ?? ""
            ]
        )
    }
    
    // MARK: - Helper Methods
    
    private func convertAmountToHex(_ amount: String?) -> String {
        guard let amount = amount,
              !amount.isEmpty,
              amount != "0" else {
            return "0x0"
        }
        
        // If already in hex format, return as is
        if amount.hasPrefix("0x") {
            return amount
        }
        
        // Convert decimal string to hex
        if let decimalValue = BigInt(amount) {
            return "0x" + String(decimalValue, radix: 16)
        }
        
        // Fallback
        return "0x0"
    }
    
    private func mapChainToBlockaidChain(_ chain: Chain) -> String {
        switch chain {
        case .ethereum:
            return "ethereum"
        case .polygon, .polygonV2:
            return "polygon"
        case .bscChain:
            return "bsc"
        case .avalanche:
            return "avalanche"
        case .arbitrum:
            return "arbitrum"
        case .optimism:
            return "optimism"
        case .base:
            return "base"
        case .solana:
            return "solana"
        case .bitcoin:
            return "bitcoin"
        case .bitcoinCash:
            return "bitcoin-cash"
        case .litecoin:
            return "litecoin"
        case .dogecoin:
            return "dogecoin"
        case .dash:
            return "dash"
        default:
            return "ethereum" // Default fallback
        }
    }
    
    private func mapBlockaidValidationToRiskLevel(_ classification: String?, resultType: String?, status: String?, hasFeatures: Bool = false) -> SecurityRiskLevel {
        logger.info("🔍 Mapping risk level - Status: '\(status ?? "nil")', Classification: '\(classification ?? "nil")', ResultType: '\(resultType ?? "nil")', HasFeatures: \(hasFeatures)")
        
        // Special case: If status is "Success" and resultType is "Benign" with NO features/warnings, this is NONE (completely secure)
        if let status = status, status.lowercased() == "success",
           let resultType = resultType, resultType.lowercased() == "benign",
           !hasFeatures {
            logger.info("✅ Success + Benign + No Features = NONE (Secure)")
            return .none
        }
        
        // Use classification if available, otherwise fall back to resultType
        let classificationToUse: String?
        if let classification = classification, !classification.isEmpty {
            classificationToUse = classification
        } else {
            classificationToUse = resultType
        }
        
        guard let classificationToUse = classificationToUse, !classificationToUse.isEmpty else { 
            logger.info("⚠️ No classification or result_type available, defaulting to medium")
            return .medium 
        }
        
        logger.info("🔍 Using classification: '\(classificationToUse)'")
        
        switch classificationToUse.lowercased() {
        case "benign":
            return .low
        case "warning":
            return .medium
        case "malicious":
            return .critical
        case "spam":
            return .medium
        default:
            logger.info("⚠️ Unknown classification '\(classificationToUse)', defaulting to medium")
            return .medium
        }
    }
    
    private func mapBlockaidFeatureToWarningType(_ featureType: String) -> SecurityWarningType {
        switch featureType.lowercased() {
        case "malicious_contract":
            return .maliciousContract
        case "suspicious_contract":
            return .suspiciousContract
        case "phishing":
            return .phishingAttempt
        case "high_value":
            return .highValueTransfer
        case "unknown_token":
            return .unknownToken
        case "rug_pull":
            return .rugPullRisk
        default:
            return .other
        }
    }
    
    private func mapBlockaidSeverityToSecuritySeverity(_ severity: String) -> SecuritySeverity {
        switch severity.lowercased() {
        case "low":
            return .info
        case "medium":
            return .warning
        case "high":
            return .error
        case "critical":
            return .critical
        default:
            return .warning
        }
    }
}

// MARK: - Blockaid API Models

struct BlockaidEVMRequest: Codable {
    let chain: String
    let data: BlockaidEVMJSONRPCData
    let metadata: BlockaidRequestMetadata
}

struct BlockaidEVMJSONRPCData: Codable {
    let method: String
    let params: [[String: String]]
}

struct BlockaidSolanaRequest: Codable {
    let chain: String
    let data: BlockaidSolanaMessageData
    let metadata: BlockaidRequestMetadata
}

struct BlockaidSolanaMessageData: Codable {
    let message: String
    let accountAddress: String
    
    enum CodingKeys: String, CodingKey {
        case message
        case accountAddress = "account_address"
    }
}

struct BlockaidBitcoinRequest: Codable {
    let chain: String
    let data: BlockaidBitcoinTransactionData
    let metadata: BlockaidRequestMetadata
}

struct BlockaidBitcoinTransactionData: Codable {
    let rawTransaction: String
    let fromAddress: String
    let toAddress: String
    let amount: String
    
    enum CodingKeys: String, CodingKey {
        case rawTransaction = "raw_transaction"
        case fromAddress = "from_address"
        case toAddress = "to_address"
        case amount
    }
}

struct BlockaidRequestMetadata: Codable {
    let domain: String
}

struct BlockaidTokenScanRequest: Codable {
    let chain: String
    let address: String
    let metadata: BlockaidRequestMetadata
}

struct BlockaidAddressScanRequest: Codable {
    let chain: String
    let address: String
    let metadata: BlockaidRequestMetadata
}

struct BlockaidSiteScanRequest: Codable {
    let url: String
    let metadata: BlockaidRequestMetadata
}

struct BlockaidTransactionScanResponse: Codable {
    let requestId: String?
    let validation: BlockaidValidation?
    let block: String?
    let chain: String?
    let accountAddress: String?
    
    enum CodingKeys: String, CodingKey {
        case requestId = "request_id"
        case validation
        case block
        case chain
        case accountAddress = "account_address"
    }
}

struct BlockaidValidation: Codable {
    let status: String?
    let classification: String?
    let resultType: String?
    let description: String?
    let reason: String?
    let features: [BlockaidFeature]?
    
    enum CodingKeys: String, CodingKey {
        case status
        case classification
        case resultType = "result_type"
        case description
        case reason
        case features
    }
}

struct BlockaidFeature: Codable {
    let type: String
    let severity: String?
    let description: String
    let address: String?
} 
