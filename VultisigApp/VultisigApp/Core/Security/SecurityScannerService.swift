//
//  SecurityScannerService.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 29/07/2025.
//

import Foundation
import OSLog

enum SecurityScannerError: Error {
    case notScanned(providerName: String)
}

class SecurityScannerService: SecurityScannerServiceProtocol {

    private let providers: [BlockaidScannerServiceProtocol]
    private let settingsService: SecurityScannerSettingsServiceProtocol
    private let factory: SecurityScannerTransactionFactoryProtocol
    private let logger = Logger(subsystem: "com.vultisig.app", category: "security-scanner-service")

    // Thread-safe set for disabled provider names
    private let disabledProvidersQueue = DispatchQueue(label: "com.vultisig.security-scanner.providers", attributes: .concurrent)
    private var _disabledProviderNames: Set<String> = []

    private var disabledProviderNames: Set<String> {
        get {
            disabledProvidersQueue.sync { _disabledProviderNames }
        }
        set {
            disabledProvidersQueue.async(flags: .barrier) { self._disabledProviderNames = newValue }
        }
    }

    init(
        providers: [BlockaidScannerServiceProtocol],
        settingsService: SecurityScannerSettingsServiceProtocol,
        factory: SecurityScannerTransactionFactoryProtocol
    ) {
        self.providers = providers
        self.settingsService = settingsService
        self.factory = factory
    }

    func scanTransaction(_ transaction: SecurityScannerTransaction) async throws -> SecurityScannerResult {
        let enabledProviders = providers.filter { !disabledProviderNames.contains($0.getProviderName()) }

        guard let firstProvider = enabledProviders.first else {
            let errorMessage = "SecurityScanner: No enabled provider available for scanning \(transaction.chain) tx"
            logger.warning("\(errorMessage)")
            throw BlockaidScannerError.scannerError(errorMessage, payload: nil)
        }

        logger.info("🔍 Scanning \(transaction.chain.name) transaction with provider: \(firstProvider.getProviderName())")
        do {
            return try await firstProvider.scanTransaction(transaction)
        } catch {
            logger.error("Scan failed with provider \(firstProvider.getProviderName()): \(error)")
            // Optionally, enhance the error to include the original error
            throw SecurityScannerError.notScanned(providerName: firstProvider.getProviderName())
        }
    }

    func isSecurityServiceEnabled() -> Bool {
        return settingsService.isEnabled
    }

    func createSecurityScannerTransaction(transaction: SendTransaction, vault: Vault) async throws -> SecurityScannerTransaction {
        return try await factory.createSecurityScanner(transaction: transaction, vault: vault)
    }

    func createSecurityScannerTransaction(transaction: SwapTransaction) async throws -> SecurityScannerTransaction {
        return try await factory.createSecurityScanner(transaction: transaction)
    }

    func createRecipientSecurityScannerTransaction(transaction: SwapTransaction) throws -> SecurityScannerTransaction {
        return try factory.createRecipientSecurityScanner(transaction: transaction)
    }

    func getSupportedChainsByFeature() -> [SecurityScannerSupport] {
        return providers.map { provider in
            let features = provider.getSupportedChains().map { (featureType, chains) in
                SecurityScannerSupport.Feature(
                    chains: chains,
                    featureType: featureType
                )
            }

            return SecurityScannerSupport(
                provider: provider.getProviderName(),
                feature: features
            )
        }
    }
}
