//
//  SwapVerifyViewModel.swift
//  VultisigApp
//

import SwiftUI
import OSLog

@MainActor
final class SwapVerifyViewModel: ObservableObject {
    private let logger = Logger(subsystem: "com.vultisig.app", category: "swap-verify")
    let securityScanViewModel = SecurityScannerViewModel()

    @Published var isAmountCorrect = false
    @Published var isFeeCorrect = false
    @Published var isApproveCorrect = false

    @Published var showSecurityScannerSheet: Bool = false
    @Published var securityScannerState: SecurityScannerState = .idle

    @Published var error: Error?
    @Published var isLoading = false
    @Published var isLoadingFees = false
    @Published var isLoadingTransaction = false
    @Published var timer: Int = 59

    func onLoad() {
        securityScanViewModel.$state
            .assign(to: &$securityScannerState)
    }

    func isValidForm(shouldApprove: Bool) -> Bool {
        if shouldApprove {
            return isAmountCorrect && isFeeCorrect && isApproveCorrect
        } else {
            return isAmountCorrect && isFeeCorrect
        }
    }

    func scan(transaction: SwapTransaction) async {
        await securityScanViewModel.scan(transaction: transaction)
    }

    func validateSecurityScanner() -> Bool {
        showSecurityScannerSheet = securityScannerState.shouldShowWarning
        return !securityScannerState.shouldShowWarning
    }

    func updateTimer(tx: SwapTransaction, vault: Vault, referredCode: String) async {
        timer -= 1
        if timer < 1 {
            await refreshData(tx: tx, vault: vault, referredCode: referredCode)
            timer = 59
        }
    }

    func refreshData(tx: SwapTransaction, vault: Vault, referredCode: String) async {
        isLoadingFees = true
        defer { isLoadingFees = false }

        do {
            let quote = try await SwapCryptoLogic.fetchQuote(tx: tx, vault: vault, referredCode: referredCode)
            tx.quote = quote
            if let balanceError = SwapCryptoLogic.balanceError(tx: tx) {
                throw balanceError
            }
            let chainSpecific = try await SwapCryptoLogic.fetchChainSpecific(tx: tx)
            tx.gas = chainSpecific.gas
            tx.thorchainFee = try await SwapCryptoLogic.thorchainFee(for: chainSpecific, tx: tx, vault: vault)
            error = nil
        } catch {
            guard (error as? URLError)?.code != .cancelled else { return }
            logger.warning("Refresh quote error: \(error.localizedDescription)")
            self.error = error
        }
    }

    func buildSwapKeysignPayload(tx: SwapTransaction, vault: Vault) async -> KeysignPayload? {
        isLoadingTransaction = true
        defer { isLoadingTransaction = false }

        do {
            return try await SwapCryptoLogic.buildSwapKeysignPayload(tx: tx, vault: vault)
        } catch {
            self.error = error
            return nil
        }
    }
}
