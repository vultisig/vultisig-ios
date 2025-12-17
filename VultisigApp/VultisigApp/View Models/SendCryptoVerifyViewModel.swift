//
//  SendCryptoVerifyViewModel.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-19.
//

import SwiftUI
import BigInt
import WalletCore


@MainActor
class SendCryptoVerifyViewModel: ObservableObject {
    
    enum FeeState {
        case idle
        case loading
        case loaded
        case failed(Error)
    }
    
    let securityScanViewModel = SecurityScannerViewModel()
    
    @Published var isAddressCorrect = false
    @Published var isAmountCorrect = false
    @Published var showAlert = false
    @Published var isLoading = false
    @Published var errorMessage = ""
    
    @Published var showSecurityScannerSheet: Bool = false
    @Published var securityScannerState: SecurityScannerState = .idle
    @Published var feeState: FeeState = .idle
    
    // Logic delegation
    private let logic = SendCryptoVerifyLogic()
    
    func onLoad() {
        securityScanViewModel.$state
            .assign(to: &$securityScannerState)
    }
    
    func loadGasInfoForSending(tx: SendTransaction) async {
        tx.isCalculatingFee = true
        isLoading = true
        errorMessage = ""
        feeState = .loading
        
        do {
            // Update balance to ensure we aren't using stale data
            await BalanceService.shared.updateBalance(for: tx.coin)
            
            let feeResult = try await logic.calculateFee(tx: tx)
            
            tx.fee = feeResult.fee
            tx.gas = feeResult.gas
            tx.isCalculatingFee = false
            isLoading = false
            feeState = .loaded
            
            validateBalanceWithFee(tx: tx)
        } catch {
            print("DEBUG: Error calculating fee: \(error)")
            // If fee estimation fails, show the real error, not "insufficient balance"
            errorMessage = error.localizedDescription
            showAlert = true
            tx.isCalculatingFee = false
            isLoading = false
            feeState = .failed(error)
        }
    }
    
    func validateBalanceWithFee(tx: SendTransaction) {
        // Validation should be based on feeState == .loaded
        guard case .loaded = feeState else { return }
        
        // Also ensure we don't show error if we are currently loading (double check)
        guard !isLoading else { return }
        
        let result = logic.validateBalanceWithFee(tx: tx)
        if !result.isValid {
            errorMessage = result.errorMessage ?? ""
            showAlert = true
            isAmountCorrect = false
        }
    }
    
    var isValidForm: Bool {
        return isAddressCorrect && isAmountCorrect
    }
    
    var signButtonDisabled: Bool {
        !isValidForm || isLoading
    }
    
    func validateForm(tx: SendTransaction, vault: Vault) async throws -> KeysignPayload {
        isLoading = true
        defer { isLoading = false }
        
        do {
            if !isValidForm {
                throw HelperError.runtimeError("mustAgreeTermsError")
            }
            
            try await logic.validateUtxosIfNeeded(tx: tx)
            let keysignPayload = try await logic.buildKeysignPayload(tx: tx, vault: vault)
            return keysignPayload
        } catch {
            throw error
        }
    }
    
    func scan(transaction: SendTransaction, vault: Vault) async {
        await securityScanViewModel.scan(transaction: transaction, vault: vault)
    }
    
    func validateSecurityScanner() -> Bool {
        showSecurityScannerSheet = securityScannerState.shouldShowWarning
        return !securityScannerState.shouldShowWarning
    }
}
