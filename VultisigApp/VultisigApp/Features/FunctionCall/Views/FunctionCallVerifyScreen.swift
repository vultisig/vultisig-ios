//
//  FunctionCallVerifyView.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 14/05/24.
//

import Foundation
import SwiftUI

struct FunctionCallVerifyScreen: View {
    @Environment(\.router) var router
    @StateObject var depositViewModel = FunctionCallViewModel()
    @StateObject var depositVerifyViewModel = FunctionCallVerifyViewModel()
    let transaction: SendTransaction
    let vault: Vault

    @State var fastPasswordPresented = false
    @State var fastVaultPassword: String = ""
    @State var isForReferral = false
    @State private var error: HelperError?
    /// Set when the pre-sign re-check finds the order is no longer cancellable.
    @State private var staleOrderMessage: String?

    var body: some View {
        Screen {
            VStack(spacing: 0) {
                if isForReferral {
                    ReferralSendOverviewView(transaction: transaction)
                } else if transaction.cosmosStakingPayload != nil {
                    stakingSummary
                } else {
                    summary
                }

                Spacer()
                pairedSignButton
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .blur(radius: depositVerifyViewModel.isLoading ? 1 : 0)
        }
        .screenTitle("verify".localized)
        .onDisappear {
            depositVerifyViewModel.isLoading = false
            // Clear password if navigating back (not forward to keysign)
            if vault.isFastVault {
                fastVaultPassword = .empty
            }
        }
        .alert(item: $error) { error in
            Alert(
                title: Text(NSLocalizedString("error", comment: "")),
                message: Text(NSLocalizedString(error.localizedDescription, comment: "")),
                dismissButton: .default(Text(NSLocalizedString("ok", comment: "")))
            )
        }
        .onLoad {
            depositVerifyViewModel.onLoad()
            Task {
                await depositVerifyViewModel.scan(transaction: transaction)
            }
        }
        .bottomSheet(isPresented: $depositVerifyViewModel.showSecurityScannerSheet) {
            SecurityScannerBottomSheet(securityScannerModel: depositVerifyViewModel.securityScannerState.result) {
                depositVerifyViewModel.showSecurityScannerSheet = false
                signAndMoveToNextView()
            } onDismissRequest: {
                depositVerifyViewModel.showSecurityScannerSheet = false
            }
        }
    }

    var stakingSummary: some View {
        CosmosStakingVerifySummaryView(
            transaction: transaction,
            vault: vault,
            feeCrypto: transaction.gasInReadable,
            feeFiat: depositViewModel.feesInReadable(tx: transaction, vault: vault),
            securityScannerState: $depositVerifyViewModel.securityScannerState
        )
    }

    var summary: some View {
        SendCryptoVerifySummaryView(
            input: SendCryptoVerifySummary(
                fromName: vault.name,
                fromAddress: transaction.fromAddress,
                toAddress: transaction.toAddress,
                network: transaction.coin.chain.name,
                networkImage: transaction.coin.chain.logo,
                memo: "",
                memoFunctionDictionary: depositViewModel.memoDictionary(for: transaction.memoFunctionDictionary),
                feeCrypto: transaction.gasInReadable,
                feeFiat: depositViewModel.feesInReadable(tx: transaction, vault: vault),
                coinImage: transaction.coin.logo,
                amount: getAmount(),
                coinTicker: transaction.coin.ticker,
                // A limit-order cancel is not a send, and the generic header
                // would call it one — "You're sending 0 RUNE" on the THORChain
                // route, or "You're sending 2 DOGE" on the L1 one, where the two
                // DOGE are dust donated to the pool. `nil` for everything else,
                // which keeps the existing presentation.
                hero: LimitOrderCancelPresentation.hero(for: transaction)
            ),
            securityScannerState: $depositVerifyViewModel.securityScannerState
        ) {
            cancelLimitOrderDisclosures
        }
    }

    /// What a limit-order cancel has to say before it is signed.
    ///
    /// These used to be an intermediate confirmation screen. That screen had no
    /// editable field — a cancel arrives with its assets, amounts and memo
    /// already fixed — so it was removed and its content moved HERE, one step
    /// closer to the signature rather than one step further from it.
    ///
    /// ⚠️ The donated-dust line is the one that must never be dropped. An L1
    /// cancel has to attach a coin for Bifrost to observe it at all, and
    /// THORNode donates whatever arrives to the pool with no refund path. On
    /// DOGE that is two whole coins of the user's own money, and a generic
    /// "network fees apply" would be actively misleading.
    @ViewBuilder
    private var cancelLimitOrderDisclosures: some View {
        if let cancel = transaction.limitCancelContext {
            VStack(alignment: .leading, spacing: 16) {
                // What actually happens on-chain: the order closes, anything
                // already filled stays paid out, and the unfilled remainder is
                // refunded. Said plainly because a user cancelling a partially
                // filled order otherwise has no way to know the filled part is
                // not coming back.
                Text("limitSwap.cancel.explanation".localized)
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textSecondary)

                if let donated = cancel.disclosures?.donatedAmount {
                    WarningView(text: String(format: "limitSwap.cancel.donatedDust".localized, donated))
                }

                if cancel.duplicateRestingOrderCount > 0 {
                    // THORChain addresses orders by (assets, ratio) + sender and
                    // cancels the FIRST match — never by tx hash. With more than
                    // one identical resting order we genuinely cannot promise
                    // which closes, so we say so rather than implying certainty.
                    WarningView(text: "limitSwap.cancel.duplicateWarning".localized)
                }

                if let balanceObjection = cancel.disclosures?.balanceObjection {
                    WarningView(text: balanceObjection)
                }

                if let staleOrderMessage {
                    WarningView(text: staleOrderMessage)
                }

                if cancel.disclosures?.canAffordCancel == false {
                    InsufficientFeeNotice(ticker: transaction.coin.chain.ticker)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// True when signing must be refused outright. Only the balance verdict
    /// qualifies: everything else on this screen is a disclosure the user is
    /// entitled to weigh for themselves.
    private var isSigningBlocked: Bool {
        transaction.limitCancelContext?.disclosures?.canAffordCancel == false
    }

    var pairedSignButton: some View {
        SigningCTAButtons(
            isFastVault: vault.isFastVault,
            isDisabled: isSigningBlocked,
            singleSignTitle: "signTransaction",
            onFastSign: { fastPasswordPresented = true },
            onPairedSign: {
                fastVaultPassword = .empty
                onSignPress()
            }
        )
        .crossPlatformSheet(isPresented: $fastPasswordPresented) {
            FastVaultEnterPasswordView(
                password: $fastVaultPassword,
                vault: vault,
                onSubmit: { onSignPress() }
            )
        }
    }

    private func getAmount() -> String {
        // Check if this is a THORChain LP operation
        if let pool = transaction.memoFunctionDictionary["pool"], !pool.isEmpty {
            // For LP operations, show context about which pool
            let cleanPoolName = ThorchainService.cleanPoolName(pool)
            // Adding source asset to its pool (THORChain RUNE or any L1 asset).
            return transaction.amountDecimal.formatForDisplay() + " " + transaction.coin.ticker + " → " + cleanPoolName + " LP"
        }

        // Default display for non-LP operations
        return transaction.amountDecimal.formatForDisplay()
    }

    private func onSignPress() {
        guard !isSigningBlocked, isCancelStillEligible() else { return }
        let canSign = depositVerifyViewModel.validateSecurityScanner()
        if canSign {
            signAndMoveToNextView()
        }
    }

    /// Re-check a limit-order cancel against storage immediately before signing.
    ///
    /// The order was snapshotted before navigation and this screen can sit open
    /// indefinitely; in that window the order can fill, expire, or already have a
    /// cancel recorded against it. Signing then spends a fee — and on L1 donates
    /// dust — for a memo that can no longer match anything.
    ///
    /// Called from BOTH gates, and the duplication is deliberate.
    /// `signAndMoveToNextView` is the true last word — the security-scanner sheet
    /// continues straight into it, and that sheet exists precisely to make the
    /// user stop and read, so an unbounded amount of time can pass between the
    /// tap and the signature. Checking in `onSignPress` as well only buys earlier
    /// feedback: the user is told the order changed instead of being walked
    /// through a scanner sheet for a transaction that will be refused anyway.
    private func isCancelStillEligible() -> Bool {
        guard let cancel = transaction.limitCancelContext else { return true }
        guard limitOrderCancelIsStillEligible(cancel, pubKeyECDSA: vault.pubKeyECDSA) else {
            staleOrderMessage = "limitSwap.cancel.orderChanged".localized
            fastPasswordPresented = false
            return false
        }
        staleOrderMessage = nil
        return true
    }

    func signAndMoveToNextView() {
        // The last gate before the ceremony starts, and the only one the
        // security-scanner continuation passes through.
        guard !isSigningBlocked, isCancelStillEligible() else { return }
        Task {
            do {
                let result = try await depositVerifyViewModel.createKeysignPayload(tx: transaction)
                await MainActor.run {
                    // Fast vaults sign server-side with no peer to pair with,
                    // so route straight into keysign (the bootstrap runs there)
                    // and skip the pairing screen. A present fast password is
                    // the fast-sign signal; an empty one means paired-sign,
                    // which keeps the QR pairing screen.
                    let context = SigningTxContext.functionCall(
                        vault: vault,
                        tx: transaction,
                        retry: SendRetrySignal()
                    )
                    if let fastPassword = fastVaultPassword.nilIfEmpty {
                        router.navigate(to: SigningRoute.keysign(.fast(
                            context: context,
                            keysignPayload: result,
                            fastVaultPassword: fastPassword
                        )))
                    } else {
                        router.navigate(to: SigningRoute.pair(
                            context: context,
                            keysignPayload: result,
                            fastVaultPassword: nil
                        ))
                    }
                }
            } catch {
                await MainActor.run {
                    self.error = error as? HelperError
                }
            }
        }
    }
}

#Preview {
    FunctionCallVerifyScreen(
        transaction: .empty(coin: .example, vault: .example),
        vault: Vault.example
    )
}
