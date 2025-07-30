//
//  SecurityScanViewModel.swift
//  VultisigApp
//
//  Created by Assistant on 2025-01-14.
//

import Foundation
import Combine
import SwiftUI

enum SecurityScannerState: Equatable {
    case idle
    case scanning
    case scanned(SecurityScannerResult)
    case notScanned(provider: String)
    
    var shouldShowWarning: Bool {
        switch self {
        case .scanned(let result):
            return !result.isSecure
        case .scanning, .notScanned, .idle:
            return false
        }
    }
    
    var result: SecurityScannerResult? {
        switch self {
        case .scanned(let result):
            return result
        case .scanning, .notScanned, .idle:
            return nil
        }
    }
}

class SecurityScannerViewModel: ObservableObject {
    @Published var state = SecurityScannerState.idle
    
    private let service: SecurityScannerServiceProtocol
    
    init(service: SecurityScannerServiceProtocol = SecurityScannerServiceFactory.buildSecurityScannerService()) {
        self.service = service
    }
    
    func scan(transaction: SendTransaction, vault: Vault) async {
        await update(state: .scanning)
        do {
            let tx = try await service.createSecurityScannerTransaction(transaction: transaction, vault: vault)
            let result = try await service.scanTransaction(tx)
            await update(state: .scanned(result))
        } catch {
            guard case let SecurityscannerError.notScanned(provider) = error else {
                return
            }
            await update(state: .notScanned(provider: provider))
        }
    }
    
    func scan(transaction: SwapTransaction, vault: Vault) async {
        await update(state: .scanning)
        do {
            let tx = try await service.createSecurityScannerTransaction(transaction: transaction)
            let result = try await service.scanTransaction(tx)
            await update(state: .scanned(result))
        } catch {
            guard case let SecurityscannerError.notScanned(provider) = error else {
                return
            }
            await update(state: .notScanned(provider: provider))
        }
    }
    
    func isScanningAvailable(for chain: Chain) -> Bool {
        service.isSecurityServiceEnabled()
    }
    
    private func update(state: SecurityScannerState) async {
        await MainActor.run { self.state = state }
    }
}
