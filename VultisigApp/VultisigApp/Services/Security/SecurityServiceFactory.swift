//
//  SecurityServiceFactory.swift
//  VultisigApp
//
//  Created by Assistant on 2025-01-14.
//

import Foundation

/// Factory for configuring the security service with different providers
struct SecurityServiceFactory {
    
    /// Configuration options for security service
    struct Configuration {
        let useBlockaid: Bool
        let isEnabled: Bool
        let blockaidCapabilities: SecurityProviderCapabilities
        
        init(
            useBlockaid: Bool = true,
            isEnabled: Bool = true,
            blockaidCapabilities: SecurityProviderCapabilities = .blockaidEVM
        ) {
            self.useBlockaid = useBlockaid
            self.isEnabled = isEnabled
            self.blockaidCapabilities = blockaidCapabilities
        }
        
        /// EVM-only configuration (current plan) - Transaction scanning only
        static let `default` = Configuration(
            blockaidCapabilities: .blockaidEVM
        )
        
        /// Full capabilities configuration (higher plan)
        static let full = Configuration(
            blockaidCapabilities: .blockaidFull
        )
        
        /// Disabled configuration
        static let disabled = Configuration(
            useBlockaid: false,
            isEnabled: false,
            blockaidCapabilities: .none
        )
        
        /// EVM-only configuration (current plan)
        static let evmOnly = Configuration(
            blockaidCapabilities: .blockaidEVM
        )
    }
    
    /// Configure the shared security service instance
    static func configure(with configuration: Configuration = .default) {
        let securityService = SecurityService.shared
        
        // Set enabled state
        securityService.setEnabled(configuration.isEnabled)
        
        guard configuration.isEnabled else {
            return
        }
        
        // Clear existing providers
        securityService.getProviders().forEach { provider in
            securityService.removeProvider(named: provider.providerName)
        }
        
        // Add Blockaid provider if enabled
        if configuration.useBlockaid {
            let blockaidProvider = BlockaidProvider(capabilities: configuration.blockaidCapabilities)
            securityService.addProvider(blockaidProvider)
        }
    }
    
    /// Get configuration from environment or user defaults
    static func getConfigurationFromEnvironment() -> Configuration {
        let useBlockaid = UserDefaults.standard.object(forKey: "VultisigUseBlockaid") as? Bool ?? true
        let isEnabled = UserDefaults.standard.object(forKey: "VultisigSecurityScanEnabled") as? Bool ?? true
        
        // Use Blockaid through proxy for real-time security scanning
        return Configuration(
            useBlockaid: useBlockaid,
            isEnabled: isEnabled
        )
    }
}

// MARK: - UserDefaults Extension

extension UserDefaults {
    
    /// Enable or disable security scanning
    func setSecurityScanEnabled(_ enabled: Bool) {
        set(enabled, forKey: "VultisigSecurityScanEnabled")
    }
    
    /// Check if security scanning is enabled
    func isSecurityScanEnabled() -> Bool {
        return object(forKey: "VultisigSecurityScanEnabled") as? Bool ?? true
    }
    
    /// Enable or disable Blockaid provider
    func setBlockaidEnabled(_ enabled: Bool) {
        set(enabled, forKey: "VultisigUseBlockaid")
    }
    
    /// Check if Blockaid provider is enabled
    func isBlockaidEnabled() -> Bool {
        return object(forKey: "VultisigUseBlockaid") as? Bool ?? true
    }
} 