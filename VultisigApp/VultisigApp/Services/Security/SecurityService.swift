//
//  SecurityService.swift
//  VultisigApp
//
//  Created by Assistant on 2025-01-14.
//

import Foundation
import OSLog

/// Main security service that manages multiple security providers
class SecurityService {
    static let shared = SecurityService()
    
    private let logger = Logger(subsystem: "security-service", category: "security")
    private var providers: [SecurityProvider] = []
    private(set) var isEnabled: Bool = true
    
    private init() {
        setupProviders()
    }
    
    // MARK: - Configuration
    
    /// Enable or disable security scanning
    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        logger.info("Security scanning \(enabled ? "enabled" : "disabled")")
    }
    
    /// Add a security provider
    func addProvider(_ provider: SecurityProvider) {
        providers.append(provider)
        logger.info("Added security provider: \(provider.providerName)")
    }
    
    /// Remove a security provider
    func removeProvider(named providerName: String) {
        providers.removeAll { $0.providerName == providerName }
        logger.info("Removed security provider: \(providerName)")
    }
    
    /// Get all available providers
    func getProviders() -> [SecurityProvider] {
        return providers
    }
    
    /// Get providers that support a specific chain
    func getProviders(for chain: Chain) -> [SecurityProvider] {
        return providers.filter { $0.supportsChain(chain) }
    }
    
    /// Get providers that support a specific chain and have a specific capability enabled
    private func getProvidersWithCapability(for chain: Chain, capability: (SecurityProviderCapabilities) -> Bool) -> [SecurityProvider] {
        return getProviders(for: chain).filter { provider in
            if let capabilityProvider = provider as? CapabilityAwareSecurityProvider {
                return capability(capabilityProvider.capabilities)
            }
            return true // Fallback for providers without capability awareness
        }
    }
    
    // MARK: - Scanning
    
    /// Scan a transaction using the first available provider for the chain with transaction scanning enabled
    func scanTransaction(_ request: SecurityScanRequest) async throws -> SecurityScanResponse {
        guard isEnabled else {
            logger.info("Security scanning is disabled, returning safe response")
            return createSafeResponse()
        }
        
        // Get providers that have transaction scanning capability enabled for this chain
        let capableProviders = getProvidersWithCapability(for: request.chain) { capabilities in
            switch request.chain.chainType {
            case .EVM:
                return capabilities.evmTransactionScanning
            case .Solana:
                return capabilities.solanaTransactionScanning
            default:
                return false
            }
        }
        
        guard let provider = capableProviders.first else {
            logger.warning("No security providers support transaction scanning for chain: \(request.chain.name)")
            return createSafeResponse()
        }
        
        do {
            logger.info("Scanning transaction with provider: \(provider.providerName)")
            let response = try await provider.scanTransaction(request)
            logger.info("Security scan completed. Risk level: \(response.riskLevel.rawValue), Warnings: \(response.warnings.count)")
            return response
        } catch {
            logger.error("Security scan failed: \(error.localizedDescription)")
            throw error
        }
    }
    
    /// Scan a transaction using all available providers with transaction scanning enabled (for maximum security)
    func scanTransactionWithAllProviders(_ request: SecurityScanRequest) async -> [SecurityScanResponse] {
        guard isEnabled else {
            logger.info("Security scanning is disabled")
            return [createSafeResponse()]
        }
        
        // Get providers that have transaction scanning capability enabled for this chain
        let capableProviders = getProvidersWithCapability(for: request.chain) { capabilities in
            switch request.chain.chainType {
            case .EVM:
                return capabilities.evmTransactionScanning
            case .Solana:
                return capabilities.solanaTransactionScanning
            default:
                return false
            }
        }
        
        guard !capableProviders.isEmpty else {
            logger.warning("No security providers support transaction scanning for chain: \(request.chain.name)")
            return [createSafeResponse()]
        }
        
        var responses: [SecurityScanResponse] = []
        
        await withTaskGroup(of: SecurityScanResponse?.self) { group in
            for provider in capableProviders {
                group.addTask {
                    do {
                        return try await provider.scanTransaction(request)
                    } catch {
                        self.logger.error("Provider \(provider.providerName) failed: \(error.localizedDescription)")
                        return nil
                    }
                }
            }
            
            for await result in group {
                if let response = result {
                    responses.append(response)
                }
            }
        }
        
        return responses.isEmpty ? [createSafeResponse()] : responses
    }
    
    /// Scan a token for security risks using available providers with token scanning enabled
    func scanToken(_ tokenAddress: String, for chain: Chain) async throws -> SecurityScanResponse {
        guard isEnabled else {
            logger.info("Security scanning is disabled, returning safe response")
            return createSafeResponse()
        }
        
        // Get providers that have token scanning capability enabled for this chain
        let capableProviders = getProvidersWithCapability(for: chain) { capabilities in
            return capabilities.tokenScanning
        }
        
        guard let provider = capableProviders.first else {
            logger.warning("No security providers support token scanning for chain: \(chain.name)")
            throw SecurityProviderError.unsupportedOperation("Token scanning not available in current plan")
        }
        
        // Check if provider has scanToken method (Blockaid does)
        if let blockaidProvider = provider as? BlockaidProvider {
            logger.info("Scanning token \(tokenAddress) with provider: \(provider.providerName)")
            let response = try await blockaidProvider.scanToken(tokenAddress, for: chain)
            logger.info("Token security scan completed. Risk level: \(response.riskLevel.rawValue)")
            return response
        }
        
        // Fallback: create a basic safe response for other providers
        logger.info("Provider \(provider.providerName) doesn't support token scanning, returning safe response")
        return createSafeResponse()
    }
    
    /// Validate an address for security risks using available providers with address validation enabled
    func validateAddress(_ address: String, for chain: Chain) async throws -> SecurityScanResponse {
        guard isEnabled else {
            logger.info("Security scanning is disabled, returning safe response")
            return createSafeResponse()
        }
        
        // Get providers that have address validation capability enabled for this chain
        let capableProviders = getProvidersWithCapability(for: chain) { capabilities in
            return capabilities.addressValidation
        }
        
        guard let provider = capableProviders.first else {
            logger.warning("No security providers support address validation for chain: \(chain.name)")
            throw SecurityProviderError.unsupportedOperation("Address validation not available in current plan")
        }
        
        // Check if provider has validateAddress method (Blockaid does)
        if let blockaidProvider = provider as? BlockaidProvider {
            logger.info("Validating address \(address) with provider: \(provider.providerName)")
            let response = try await blockaidProvider.validateAddress(address, for: chain)
            logger.info("Address validation completed. Risk level: \(response.riskLevel.rawValue)")
            return response
        }
        
        // Fallback: create a basic safe response for other providers
        logger.info("Provider \(provider.providerName) doesn't support address validation, returning safe response")
        return createSafeResponse()
    }
    
    // MARK: - Convenience Methods
    
    /// Create a security scan request from a keysign payload
    func createSecurityScanRequest(from payload: KeysignPayload) -> SecurityScanRequest {
        let transactionType = determineTransactionType(from: payload)
        
        return SecurityScanRequest(
            chain: payload.coin.chain,
            transactionType: transactionType,
            fromAddress: payload.coin.address,
            toAddress: payload.toAddress,
            amount: payload.toAmount.description,
            data: payload.memo,
            metadata: [
                "memo": payload.memo ?? "",
                "chainSpecific": payload.chainSpecific
            ]
        )
    }
    
    /// Create a security scan request from a send transaction
    func createSecurityScanRequest(from tx: SendTransaction) -> SecurityScanRequest {
        return SecurityScanRequest(
            chain: tx.coin.chain,
            transactionType: .transfer,
            fromAddress: tx.fromAddress,
            toAddress: tx.toAddress,
            amount: tx.amount,
            data: nil,
            metadata: [
                "memo": tx.memo,
                "sendMaxAmount": tx.sendMaxAmount,
                "gas": tx.gas.description
            ]
        )
    }
    
    // MARK: - Private Methods
    
    private func setupProviders() {
        // This is now handled by SecurityServiceFactory.configure()
        // to allow for proper capability configuration
        
        // Future: Add other providers here
        // addProvider(OtherSecurityProvider())
    }
    
    private func createSafeResponse() -> SecurityScanResponse {
        return SecurityScanResponse(
            provider: "None",
            isSecure: true,
            riskLevel: .low,
            warnings: [],
            recommendations: [],
            metadata: nil
        )
    }
    
    private func determineTransactionType(from payload: KeysignPayload) -> SecurityTransactionType {
        // Check if it's a token transfer vs native transfer
        if !payload.coin.isNativeToken {
            return .transfer
        }
        
        // Check memo for swap indicators
        if let memo = payload.memo, !memo.isEmpty {
            let memoUpper = memo.uppercased()
            if memoUpper.contains("SWAP:") || memoUpper.contains("=") {
                return .swap
            }
            if memoUpper.contains("ADD:") || memoUpper.contains("+:") {
                return .defiInteraction
            }
        }
        
        // Check for contract interaction based on chain and memo/data
        if payload.coin.chain.chainType == .EVM {
            // For EVM chains, contract interactions would typically have data
            // Since we don't have direct access to transaction data in the current structure,
            // we'll check if it's a non-native token transfer as an indicator
            if !payload.coin.isNativeToken {
                return .contractInteraction
            }
        }
        
        return .transfer
    }
}

// MARK: - Extensions

extension SecurityService {
    /// Helper method to check if security scanning is available for a chain
    func isSecurityScanningAvailable(for chain: Chain) -> Bool {
        return !getProviders(for: chain).isEmpty
    }
    
    /// Get a summary of all available security providers
    func getProviderSummary() -> String {
        let providerNames = providers.map { $0.providerName }
        return "Available security providers: \(providerNames.joined(separator: ", "))"
    }
} 