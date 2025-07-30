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
        guard isScanningAvailable(for: transaction.coin.chain) else { return }
        await scan(transactionType: .send(transaction, vault))
    }
    
    func scan(transaction: SwapTransaction, vault: Vault) async {
        guard isScanningAvailable(for: transaction.fromCoin.chain) else { return }
        await scan(transactionType: .swap(transaction))
    }
    
    private func scan(transactionType: SecurityScannerTransactionType) async {
        do {
            let tx: SecurityScannerTransaction
            switch transactionType {
            case .swap(let swapTransaction):
                tx = try await service.createSecurityScannerTransaction(transaction: swapTransaction)
            case .send(let sendTransaction, let vault):
                tx = try await service.createSecurityScannerTransaction(transaction: sendTransaction, vault: vault)
            }
            await update(state: .scanning)
            
            let result = try await service.scanTransaction(tx)
            await update(state: .scanned(result))
        } catch {
            if case let SecurityscannerError.notScanned(provider) = error {
                await update(state: .notScanned(provider: provider))
            } else {
                await update(state: .idle)
            }
        }
    }
    
    func isScanningAvailable(for chain: Chain) -> Bool {
        service.isSecurityServiceEnabled()
    }
    
    private func update(state: SecurityScannerState) async {
        await MainActor.run { self.state = state }
    }
    
    private enum SecurityScannerTransactionType {
        case swap(SwapTransaction)
        case send(SendTransaction, Vault)
    }
}
