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
class SecurityScannerViewModel: ObservableObject {
    
    @Published var isScanning = false
    @Published var scanResponse: SecurityScannerResult?
    @Published var errorMessage: String?
    @Published var showAlert = false
    @Published var userAcknowledgedRisk = false
    
    private let service: SecurityScannerServiceProtocol
    private var cancellables = Set<AnyCancellable>()
    
    init(service: SecurityScannerServiceProtocol = SecurityScannerServiceFactory.buildSecurityScannerService()) {
        self.service = service
    }
    
    // MARK: - Computed Properties
    
    var hasResponse: Bool {
        return scanResponse != nil
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
//    func scanTransaction(_ request: SecurityScanRequest) async {
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
//    }
    
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
        service.isSecurityServiceEnabled()
    }
}
