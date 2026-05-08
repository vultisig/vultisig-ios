//
//  SwapVerifyViewModel.swift
//  VultisigApp
//

import SwiftUI
import OSLog

@MainActor
final class SwapVerifyViewModel: ObservableObject {
    private let logger = Logger(subsystem: "com.vultisig.app", category: "swap-verify")
    private let interactor: SwapInteractor
    let securityScanViewModel = SecurityScannerViewModel()

    init(interactor: SwapInteractor = DefaultSwapInteractor.live) {
        self.interactor = interactor
    }

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
            let result = try await interactor.fetchQuote(
                draft: SwapDraft(from: tx),
                vault: vault,
                referredCode: referredCode
            )
            if let result {
                tx.quote = result.quote
                tx.vultDiscountBps = result.vultDiscountBps
                tx.referralDiscountBps = result.referralDiscountBps
            }
            if let balanceError = SwapCryptoLogic.balanceError(draft: SwapDraft(from: tx)) {
                throw balanceError
            }
            let draft = SwapDraft(from: tx)
            let chainSpecific = try await interactor.fetchChainSpecific(draft: draft)
            tx.gas = chainSpecific.gas
            tx.thorchainFee = try await interactor.computeThorchainFee(
                chainSpecific: chainSpecific,
                draft: draft,
                vault: vault
            )
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
            return try await interactor.buildSwapKeysignPayload(draft: SwapDraft(from: tx), vault: vault)
        } catch {
            self.error = error
            return nil
        }
    }
}
