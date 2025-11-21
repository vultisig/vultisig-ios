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
    
    private let utxo = BlockchairService.shared
    private let blockChainService = BlockChainService.shared
    
    func onLoad() {
        securityScanViewModel.$state
            .assign(to: &$securityScannerState)
    }
    
    var isValidForm: Bool {
        return isAddressCorrect && isAmountCorrect
    }
    
    var signButtonDisabled: Bool {
        !isValidForm || isLoading
    }
    
    func validateForm(tx: SendTransaction, vault: Vault) async throws -> KeysignPayload {
        await MainActor.run { isLoading = true }
        do {
            if !isValidForm {
                throw HelperError.runtimeError("mustAgreeTermsError")
            }
            
            try await validateUtxosIfNeeded(tx: tx)
            let keysignPayload = try await buildKeysignPayload(tx: tx, vault: vault)
            await MainActor.run { isLoading = false }
            return keysignPayload
        } catch {
            await MainActor.run { isLoading = false }
            throw error
        }
    }
    
    func validateUtxosIfNeeded(tx: SendTransaction) async throws {
        if tx.coin.chain.chainType == ChainType.UTXO {
            do {
                _ = try await utxo.fetchBlockchairData(coin: tx.coin)
            } catch {
                print("Failed to fetch UTXO data from Blockchair, error: \(error.localizedDescription)")
                throw HelperError.runtimeError("Failed to fetch UTXO data. Please check your internet connection and try again.")
            }
        }
    }
    
    func buildKeysignPayload(tx: SendTransaction, vault: Vault) async throws -> KeysignPayload {
        do {
            let chainSpecific = try await blockChainService.fetchSpecific(tx: tx)
            
            return try await KeysignPayloadFactory().buildTransfer(
                coin: tx.coin,
                toAddress: tx.toAddress,
                amount: tx.amountInRaw,
                memo: tx.memo,
                chainSpecific: chainSpecific,
                vault: vault
            )
            
        } catch {
            // Handle UTXO-specific errors with more user-friendly messages
            let errorMessage: String
            switch error {
            case KeysignPayloadFactory.Errors.notEnoughUTXOError:
                errorMessage = NSLocalizedString("notEnoughUTXOError", comment: "")
            case KeysignPayloadFactory.Errors.utxoTooSmallError:
                errorMessage = NSLocalizedString("utxoTooSmallError", comment: "")
            case KeysignPayloadFactory.Errors.utxoSelectionFailedError:
                errorMessage = NSLocalizedString("utxoSelectionFailedError", comment: "")
            case KeysignPayloadFactory.Errors.notEnoughBalanceError:
                errorMessage = NSLocalizedString("notEnoughBalanceError", comment: "")
            default:
                errorMessage = error.localizedDescription
            }
            throw HelperError.runtimeError(errorMessage)
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
