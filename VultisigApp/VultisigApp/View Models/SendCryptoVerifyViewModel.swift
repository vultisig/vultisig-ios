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
    let securityScanViewModel = SecurityScannerViewModel()

    @Published var isAddressCorrect = false
    @Published var isAmountCorrect = false
    @Published var showAlert = false
    @Published var isLoading = false
    @Published var errorMessage = ""

    @Published var showSecurityScannerSheet: Bool = false
    @Published var securityScannerState: SecurityScannerState = .idle

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
        // Ensure balance is loaded before validation (protects against stale/empty balances)
        await BalanceService.shared.updateBalance(for: tx.coin)
        
        // For non-native tokens, also update native token balance (needed for gas validation)
        if !tx.coin.isNativeToken {
            if let vault = tx.vault ?? AppViewModel.shared.selectedVault,
               let nativeToken = vault.coins.nativeCoin(chain: tx.coin.chain) {
                await BalanceService.shared.updateBalance(for: nativeToken)
            }
        }
        do {
            let feeResult = try await logic.calculateFee(tx: tx)

            tx.fee = feeResult.fee
            tx.gas = feeResult.gas

            // Adjust amount for max send if fee changed (only for native tokens where fee is deducted from balance)
            if tx.sendMaxAmount && tx.coin.isNativeToken {
                let balance = tx.coin.rawBalance.toBigInt(decimals: tx.coin.decimals)
                let newAmount = balance - tx.fee

                if newAmount > 0 {
                    let decimals = tx.coin.decimals
                    let amountDecimal = Decimal(string: String(newAmount)) ?? 0
                    let formattedAmount = amountDecimal / pow(10, decimals)
                    tx.amount = "\(formattedAmount)"
                }
            }

            tx.isCalculatingFee = false
            isLoading = false

            validateBalanceWithFee(tx: tx)
        } catch {
            print("DEBUG: Error calculating fee: \(error)")
            errorMessage = error.localizedDescription
            showAlert = true
            tx.isCalculatingFee = false
            isLoading = false
        }
    }

    func validateBalanceWithFee(tx: SendTransaction) {
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
