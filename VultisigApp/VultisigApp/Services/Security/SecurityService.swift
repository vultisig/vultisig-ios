//
//  SecurityService.swift
//  VultisigApp
//
//  Created by Assistant on 2025-01-14.
//

import Foundation
import OSLog
import WalletCore

/// Main security service that manages multiple security providers
class SecurityService {
    static let shared = SecurityService()
    
    private let logger = Logger(subsystem: "security-service", category: "security")
    internal var providers: [SecurityProvider] = []
    private(set) var isEnabled: Bool = true
    
    private init() {
        // Call setupProviders for initialization hook, even though it's currently empty.
        // See setupProviders() documentation for why this pattern is maintained.
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
            case .UTXO:
                return capabilities.bitcoinTransactionScanning
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
            case .UTXO:
                return capabilities.bitcoinTransactionScanning
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
    
    /// Scan a site/URL for security risks using available providers with site scanning enabled
    func scanSite(_ url: String) async throws -> SecurityScanResponse {
        guard isEnabled else {
            logger.info("Security scanning is disabled, returning safe response")
            return createSafeResponse()
        }
        
        // Get providers that have site scanning capability enabled
        let capableProviders = providers.filter { provider in
            if let capabilityAware = provider as? CapabilityAwareSecurityProvider {
                return capabilityAware.capabilities.siteScanning
            }
            return false
        }
        
        guard let provider = capableProviders.first else {
            logger.warning("No security providers support site scanning")
            throw SecurityProviderError.unsupportedOperation("Site scanning not available in current plan")
        }
        
        // Check if provider has scanSite method (Blockaid does)
        if let blockaidProvider = provider as? BlockaidProvider {
            logger.info("Scanning site \(url) with provider: \(provider.providerName)")
            let response = try await blockaidProvider.scanSite(url)
            logger.info("Site security scan completed. Risk level: \(response.riskLevel.rawValue)")
            return response
        }
        
        // Fallback: create a basic safe response for other providers
        logger.info("Provider \(provider.providerName) doesn't support site scanning, returning safe response")
        return createSafeResponse()
    }
    
    // MARK: - Convenience Methods
    
    /// Create a security scan request from a keysign payload
    func createSecurityScanRequest(from payload: KeysignPayload) -> SecurityScanRequest {
        let transactionType = determineTransactionType(from: payload)
        
        // For Solana, we need to create the transaction data
        var transactionData: String? = payload.memo
        
        if payload.coin.chain == .solana {
            do {
                let inputData = try SolanaHelper.getPreSignedInputData(keysignPayload: payload)
                transactionData = inputData.base64EncodedString()
            } catch {
                logger.error("Failed to create Solana transaction data: \(error)")
                transactionData = payload.memo
            }
        }
        
        return SecurityScanRequest(
            chain: payload.coin.chain,
            transactionType: transactionType,
            fromAddress: payload.coin.address,
            toAddress: payload.toAddress,
            amount: payload.toAmount.description,
            data: transactionData,
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
        // This method is intentionally empty but kept for several important reasons:
        //
        // 1. **Initialization Hook**: Called in init() to maintain a clear initialization pattern
        //    even though provider setup has been delegated to SecurityServiceFactory
        //
        // 2. **Future Direct Setup**: If we need to add default providers that should always
        //    be available regardless of configuration, they would go here
        //
        // 3. **Testing**: Tests can override SecurityService to add mock providers directly
        //    in setupProviders without going through the factory
        //
        // 4. **Backwards Compatibility**: If we need to support legacy provider setup in the
        //    future, this method provides the hook without changing the init pattern
        //
        // Current provider setup is handled by SecurityServiceFactory.configure() which:
        // - Reads configuration from environment/UserDefaults
        // - Conditionally adds providers based on settings
        // - Manages provider lifecycle and capabilities
        //
        // This separation of concerns allows for more flexible configuration while
        // maintaining a clean initialization pattern in the SecurityService itself.
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
        // Check for swap payload first - this is the most reliable indicator
        if payload.swapPayload != nil {
            return .swap
        }
        
        // Check for token approval
        if payload.approvePayload != nil {
            return .tokenApproval
        }
        
        // Check for EVM token transfers (ERC20/BEP20/etc)
        if payload.coin.chain.chainType == .EVM && !payload.coin.isNativeToken {
            return .contractInteraction
        }
        
        // Default to transfer for all other cases (native token transfers)
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
