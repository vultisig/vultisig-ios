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
    @Published var hasBalanceError = false

    @Published var showSecurityScannerSheet: Bool = false
    @Published var securityScannerState: SecurityScannerState = .idle

    // Logic delegation
    private let logic = SendCryptoVerifyLogic()

    func onLoad() {
        securityScanViewModel.$state
            .assign(to: &$securityScannerState)
    }

    func loadGasInfoForSending(tx: LegacySendTransaction) async {
        tx.isCalculatingFee = true
        isLoading = true
        errorMessage = ""
        hasBalanceError = false
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
            // Migration shim: SendCryptoVerifyLogic now takes the immutable
            // struct; convert at the boundary. Will be removed once
            // SendCryptoVerifyViewModel itself holds SendTransaction.
            guard let vault = tx.txVault else {
                errorMessage = "No vault available for fee calculation"
                showAlert = true
                tx.isCalculatingFee = false
                isLoading = false
                return
            }
            let converted = SendTransaction.fromLegacy(tx, vault: vault)
            let feeResult = try await logic.calculateFee(tx: converted)

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

    func validateBalanceWithFee(tx: LegacySendTransaction) {
        guard let vault = tx.txVault else {
            errorMessage = "No vault available for balance validation"
            showAlert = true
            isAmountCorrect = false
            hasBalanceError = true
            return
        }
        let converted = SendTransaction.fromLegacy(tx, vault: vault)
        let result = logic.validateBalanceWithFee(tx: converted)
        if !result.isValid {
            errorMessage = result.errorMessage ?? ""
            showAlert = true
            isAmountCorrect = false
            hasBalanceError = true
        }
    }

    var isValidForm: Bool {
        return isAddressCorrect && isAmountCorrect
    }

    var signButtonDisabled: Bool {
        !isValidForm || isLoading || hasBalanceError
    }

    func validateForm(tx: LegacySendTransaction, vault: Vault) async throws -> KeysignPayload {
        isLoading = true
        defer { isLoading = false }

        do {
            if !isValidForm {
                throw HelperError.runtimeError("mustAgreeTermsError")
            }

            let converted = SendTransaction.fromLegacy(tx, vault: vault)
            try await logic.validateUtxosIfNeeded(tx: converted)
            let keysignPayload = try await logic.buildKeysignPayload(tx: converted, vault: vault)
            return keysignPayload
        } catch {
            throw error
        }
    }

    func scan(transaction: LegacySendTransaction, vault: Vault) async {
        // Migration shim: convert legacy → immutable struct at the boundary.
        // Drop this conversion (and the wrapping `transaction:vault:` signature)
        // once SendCryptoVerifyViewModel itself holds the new struct.
        let converted = SendTransaction.fromLegacy(transaction, vault: vault)
        await securityScanViewModel.scan(transaction: converted)
    }

    func validateSecurityScanner() -> Bool {
        showSecurityScannerSheet = securityScannerState.shouldShowWarning
        return !securityScannerState.shouldShowWarning
    }
}
