//
//  SecurityScanViewModel.swift
//  VultisigApp
//
//  Created by Assistant on 2025-01-14.
//

import Foundation
import Combine
import SwiftUI

@MainActor
class SecurityScanViewModel: ObservableObject {
    
    @Published var isScanning = false
    @Published var scanResponse: SecurityScanResponse?
    @Published var errorMessage: String?
    @Published var showAlert = false
    @Published var userAcknowledgedRisk = false
    
    private let securityService = SecurityService.shared
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Computed Properties
    
    var showBanner: Bool {
        hasResponse && !isSecure
    }
    
    var hasResponse: Bool {
        return scanResponse != nil
    }
    
    var hasWarnings: Bool {
        return scanResponse?.hasWarnings ?? false
    }
    
    var isSecure: Bool {
        return scanResponse?.isSecure ?? true
    }
    
    var canProceed: Bool {
        // User can proceed if:
        // 1. No scan response yet (scanning not performed)
        // 2. Transaction is secure
        // 3. User has acknowledged the risk
        return scanResponse == nil || isSecure || userAcknowledgedRisk
    }
    
    var riskLevel: SecurityRiskLevel {
        return scanResponse?.riskLevel ?? .low
    }
    
    var warningMessages: [String] {
        return scanResponse?.warningMessages ?? []
    }
    
    var providerName: String {
        return scanResponse?.provider ?? "Unknown"
    }
    
    var recommendations: [String] {
        return scanResponse?.recommendations ?? []
    }
    
    // MARK: - UI Colors
    
    var backgroundColor: Color {
        guard let response = scanResponse else { return Color.green.opacity(0.35) }
        
        switch response.riskLevel {
        case .none:
            return Color.green.opacity(0.35)
        case .low:
            return Color.green.opacity(0.35)
        case .medium:
            return Color.yellow.opacity(0.35)
        case .high:
            return Color.orange.opacity(0.35)
        case .critical:
            return Color.red.opacity(0.35)
        }
    }
    
    var borderColor: Color {
        guard let response = scanResponse else { return Color.green }
        
        switch response.riskLevel {
        case .none:
            return Color.green
        case .low:
            return Color.green
        case .medium:
            return Color.yellow
        case .high:
            return Color.orange
        case .critical:
            return Color.red
        }
    }
    
    var iconName: String {
        guard let response = scanResponse, !response.isSecure else { return "" }
        
        switch response.riskLevel {
        case .none:
            return "checkmark.shield"
        case .low:
            return "info.circle"
        case .medium:
            return "exclamationmark.triangle"
        case .high:
            return "exclamationmark.triangle.fill"
        case .critical:
            return "xmark.shield"
        }
    }
    
    var iconColor: Color {
        guard let response = scanResponse else { return Color.green }
        
        switch response.riskLevel {
        case .none:
            return Color.green
        case .low:
            return Color.green
        case .medium:
            return Color.yellow
        case .high:
            return Color.orange
        case .critical:
            return Color.red
        }
    }
    
    // MARK: - Scanning Methods
    
    /// Scan a transaction from a KeysignPayload
    func scanTransaction(from payload: KeysignPayload) async {
        let request = securityService.createSecurityScanRequest(from: payload)
        await scanTransaction(request)
    }
    
    /// Scan a transaction from a SendTransaction
    func scanTransaction(from tx: SendTransaction) async {
        let request = securityService.createSecurityScanRequest(from: tx)
        await scanTransaction(request)
    }
    
    /// Scan a transaction with a custom request
    func scanTransaction(_ request: SecurityScanRequest) async {
        isScanning = true
        errorMessage = nil
        
        do {
            let response = try await securityService.scanTransaction(request)
            self.scanResponse = response
        } catch {
            self.errorMessage = error.localizedDescription
            self.showAlert = true
        }
        
        isScanning = false
    }
    
    /// Reset the scan state
    func resetScan() {
        scanResponse = nil
        errorMessage = nil
        isScanning = false
        showAlert = false
        userAcknowledgedRisk = false
    }
    
    /// Check if security scanning is available for a chain
    func isScanningAvailable(for chain: Chain) -> Bool {
        return securityService.isSecurityScanningAvailable(for: chain)
    }
    
    /// Scan a token for security risks
    func scanToken(address: String, chain: Chain) async {
        guard securityService.isEnabled else { return }
        
        isScanning = true
        errorMessage = nil
        showAlert = false
        
        do {
            let response = try await securityService.scanToken(address, for: chain)
            self.scanResponse = response
            

            
        } catch {
            self.errorMessage = "Failed to scan token: \(error.localizedDescription)"
            self.showAlert = true

        }
        
        isScanning = false
    }
    
    /// Validate an address for security risks
    func validateAddress(_ address: String, chain: Chain) async {
        guard securityService.isEnabled else { return }
        
        isScanning = true
        errorMessage = nil
        showAlert = false
        
        do {
            let response = try await securityService.validateAddress(address, for: chain)
            self.scanResponse = response
            

            
        } catch {
            self.errorMessage = "Failed to validate address: \(error.localizedDescription)"
            self.showAlert = true

        }
        
        isScanning = false
    }
    
    // MARK: - Utility Methods
    
    /// Get a user-friendly summary of the scan results
    func getScanSummary() -> String {
        guard let response = scanResponse else {
            return "No scan results available"
        }
        
        guard !response.isSecure else {
            return ""
        }
            
        let warningCount = response.warnings.count
        let riskLevel = response.riskLevel.displayName
        return "Security scan detected \(warningCount) warning\(warningCount == 1 ? "" : "s") with \(riskLevel) risk level."
    }
    
    /// Get warnings grouped by severity
    func getWarningsGroupedBySeverity() -> [SecuritySeverity: [SecurityWarning]] {
        guard let response = scanResponse else { return [:] }
        
        return Dictionary(grouping: response.warnings) { $0.severity }
    }
    
    /// Get the highest severity warning
    func getHighestSeverityWarning() -> SecurityWarning? {
        guard let response = scanResponse else { return nil }
        
        return response.warnings.max { warning1, warning2 in
            let severity1 = getSeverityPriority(warning1.severity)
            let severity2 = getSeverityPriority(warning2.severity)
            return severity1 < severity2
        }
    }
    
    private func getSeverityPriority(_ severity: SecuritySeverity) -> Int {
        switch severity {
        case .info: return 1
        case .warning: return 2
        case .error: return 3
        case .critical: return 4
        }
    }
}

// MARK: - SwiftUI Integration

extension SecurityScanViewModel {
    
    /// Get an alert for displaying scan errors
    var scanErrorAlert: Alert {
        Alert(
            title: Text("Security Scan Error"),
            message: Text(errorMessage ?? "An unknown error occurred during security scanning."),
            dismissButton: .default(Text("OK")) {
                self.showAlert = false
            }
        )
    }
    
    /// Get an alert for displaying high-risk warnings
    func getHighRiskAlert() -> Alert? {
        guard let response = scanResponse,
              response.riskLevel == .high || response.riskLevel == .critical else {
            return nil
        }
        
        let title = response.riskLevel == .critical ? "Critical Security Risk" : "High Security Risk"
        let message = response.warnings.first?.message ?? "This transaction has been flagged as potentially dangerous."
        
        return Alert(
            title: Text(title),
            message: Text(message),
            primaryButton: .destructive(Text("Proceed Anyway")) {
                self.userAcknowledgedRisk = true
            },
            secondaryButton: .cancel(Text("Cancel"))
        )
    }
} 
