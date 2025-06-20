//
//  SecurityServiceFactory.swift
//  VultisigApp
//
//  Created by Assistant on 2025-01-14.
//

import Foundation

/// Factory for configuring the security service with all available providers
struct SecurityServiceFactory {
    
    /// Simple configuration for the security service
    struct Configuration {
        let isEnabled: Bool
        
        init(isEnabled: Bool = true) {
            self.isEnabled = isEnabled
        }
        
        static let `default` = Configuration()
        static let disabled = Configuration(isEnabled: false)
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
        
        // Add all available and enabled providers
        addAvailableProviders(to: securityService)
    }
    
    /// Add all available providers that are enabled
    private static func addAvailableProviders(to securityService: SecurityService) {
        for providerType in AvailableSecurityProvider.allCases {
            if let provider = providerType.createProvider() {
                securityService.addProvider(provider)
                print("[SecurityServiceFactory] Added provider: \(providerType.displayName)")
            } else {
                print("[SecurityServiceFactory] Skipped disabled provider: \(providerType.displayName)")
            }
        }
    }
    
    /// Get configuration from environment or user defaults
    static func getConfigurationFromEnvironment() -> Configuration {
        let isEnabled = UserDefaults.standard.object(forKey: "VultisigSecurityScanEnabled") as? Bool ?? true
        return Configuration(isEnabled: isEnabled)
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
    
    /// Enable or disable a specific security provider
    func setSecurityProviderEnabled(_ providerName: String, enabled: Bool) {
        set(enabled, forKey: "VultisigSecurityProvider_\(providerName)")
    }
    
    /// Check if a specific security provider is enabled
    func isSecurityProviderEnabled(_ providerName: String) -> Bool {
        return object(forKey: "VultisigSecurityProvider_\(providerName)") as? Bool ?? true
    }
} 