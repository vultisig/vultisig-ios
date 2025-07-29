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
    
//    private let securityService = SecurityService.shared
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Computed Properties
    
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
        guard let response = scanResponse else { return "checkmark.shield" }
        
        if response.isSecure {
            return "checkmark.shield"
        } else {
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
//        let request = securityService.createSecurityScanRequest(from: payload)
//        await scanTransaction(request)
    }
    
    /// Scan a transaction from a SendTransaction
    func scanTransaction(from tx: SendTransaction) async {
//        let request = securityService.createSecurityScanRequest(from: tx)
//        await scanTransaction(request)
    }
    
    /// Scan a transaction with a custom request
    func scanTransaction(_ request: SecurityScanRequest) async {
//        isScanning = true
//        errorMessage = nil
//        
//        do {
//            let response = try await securityService.scanTransaction(request)
//            self.scanResponse = response
//            
//
//            
//        } catch {
//            self.errorMessage = error.localizedDescription
//            self.showAlert = true
//
//        }
//        
//        isScanning = false
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
        fatalError()
//        return securityService.isSecurityScanningAvailable(for: chain)
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
