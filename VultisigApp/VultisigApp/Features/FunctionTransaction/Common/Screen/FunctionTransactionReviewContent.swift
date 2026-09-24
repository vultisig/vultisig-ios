//
//  FunctionTransactionReviewContent.swift
//  VultisigApp
//
//  The review of a DeFi operation (bond, stake, LP, governance, limit
//  cancel and the rest), shown in the keysign review sheet. Signing hands
//  its route to the review presenter, which pushes it once the sheet has
//  closed.
//

import SwiftUI

struct FunctionTransactionReviewContent: View {
    let transaction: SendTransaction
    let vault: Vault
    /// The presentation this review was shown under, handed back when it
    /// proceeds so a late sign step cannot proceed a later review.
    let presentationID: UUID

    @StateObject private var pricing = FunctionTransactionPricingViewModel()
    @StateObject private var viewModel = FunctionTransactionVerifyViewModel()
    @Environment(KeysignReviewPresenter.self) private var reviewPresenter

    @State private var fastPasswordPresented = false
    @State private var fastVaultPassword: String = ""
    @State private var error: HelperError?
    @State private var isScanComplete = false
    /// Set when the pre-sign re-check finds the order is no longer cancellable.
    @State private var staleOrderMessage: String?

    var body: some View {
        KeysignReviewSheet(
            title: "overview".localized,
            scanRing: KeysignReviewScanRing(viewModel.securityScannerState, isScanComplete: isScanComplete),
            verdict: verdict,
            onClose: reviewPresenter.dismiss
        ) {
            FunctionTransactionReviewSummaryView(summary: summary) {
                cancelLimitOrderDisclosures
            }
            .blur(radius: viewModel.isLoading ? 1 : 0)
        } footer: {
            SigningCTAButtons(
                isFastVault: vault.offersFastSigning,
                isDisabled: isSigningBlocked,
                singleSignTitle: "signTransaction",
                onFastSign: { fastPasswordPresented = true },
                onPairedSign: {
                    fastVaultPassword = .empty
                    onSignPress()
                }
            )
        }
        .onDisappear {
            viewModel.isLoading = false
            if vault.offersFastSigning {
                fastVaultPassword = .empty
            }
        }
        .alert(item: $error) { error in
            Alert(
                title: Text("error".localized),
                message: Text(error.localizedDescription.localized),
                dismissButton: .default(Text("ok".localized))
            )
        }
        .onLoad {
            viewModel.onLoad()
            Task {
                async let hero: Void = viewModel.loadResolvedHero(transaction: transaction)
                await viewModel.scan(transaction: transaction)
                isScanComplete = true
                await hero
            }
        }
        .task { await viewModel.loadValidators(transaction: transaction) }
        .crossPlatformSheet(isPresented: $fastPasswordPresented) {
            FastVaultEnterPasswordView(
                isPresented: $fastPasswordPresented,
                password: $fastVaultPassword,
                vault: vault,
                onSubmit: { onSignPress() }
            )
        }
    }

    private var verdict: KeysignReviewVerdict? {
        guard viewModel.showSecurityScannerSheet, let result = viewModel.securityScannerState.result else { return nil }
        return KeysignReviewVerdict(
            result: result,
            onGoBack: { viewModel.showSecurityScannerSheet = false },
            onContinueAnyway: {
                viewModel.showSecurityScannerSheet = false
                signAndProceed()
            }
        )
    }

    // MARK: - Summary

    private var summary: FunctionTransactionReviewSummary {
        let resolverHero = TransactionHeroResolver.hero(on: .functionCallVerify, for: .initiating(transaction))
        // The resolver owns provider precedence; a staking operation has only
        // the resolver's hero, as it always has.
        let hero = transaction.cosmosStakingPayload == nil
            ? viewModel.resolvedHero ?? resolverHero
            : resolverHero
        return FunctionTransactionReviewSummary(
            hero: hero ?? .send(title: nil, coin: plainAmount),
            vaultName: vault.name,
            vaultAddress: transaction.fromAddress,
            rows: rows,
            fee: (amount: transaction.gasInReadable, fiat: pricing.feesInReadable(tx: transaction, vault: vault)),
            additionalRows: cancelLimitOrderRows
        )
    }

    private var rows: [FunctionTransactionReviewSummary.Row] {
        var rows: [FunctionTransactionReviewSummary.Row] = []
        if let staking = transaction.cosmosStakingPayload {
            rows += CosmosStakingValidatorRows.rows(for: staking, validators: viewModel.validatorsByAddress)
                .map { .init(label: $0.labelKey.localized, value: $0.value) }
        } else {
            if transaction.toAddress.isNotEmpty {
                rows.append(.init(label: "to".localized, value: transaction.toAddress))
            }
            let memoRows = pricing.memoDictionary(for: transaction.memoFunctionDictionary)
            for key in memoRows.keys.sorted() {
                if let value = memoRows[key] {
                    rows.append(.init(label: key.localized, value: value))
                }
            }
        }
        rows.append(.init(label: "network".localized, value: transaction.coin.chain.name, image: transaction.coin.chain.logo))
        return rows
    }

    /// The amount when no hero describes it. A THORChain LP operation also
    /// says which pool it adds to.
    private var plainAmount: HeroCoinAmount {
        let amount = transaction.amountDecimal.formatForDisplay()
        let ticker = transaction.coin.ticker
        if let pool = transaction.memoFunctionDictionary["pool"], !pool.isEmpty {
            // The pool reads after the ticker, so the text carries both.
            let text = "\(amount) \(ticker) → \(ThorchainService.cleanPoolName(pool)) LP"
            return HeroCoinAmount(amount: text, ticker: "", logo: transaction.coin.logo)
        }
        return HeroCoinAmount(amount: amount, ticker: ticker, logo: transaction.coin.logo)
    }

    /// The dust an L1 cancel attaches, as a cost row beside the network fee.
    /// It is real, non-refundable money, so its exact amount stays disclosed,
    /// but as a normal cost rather than an alarm. Empty on the THORChain
    /// route, which attaches nothing.
    private var cancelLimitOrderRows: [FunctionTransactionReviewSummary.Row] {
        guard let donated = transaction.limitCancelContext?.disclosures?.donatedAmount else { return [] }
        return [.init(label: "limitSwap.cancel.donatedDustRow".localized, value: donated)]
    }

    /// What a limit-order cancel has to say before it is signed: that filled
    /// parts stay paid out, when more than one identical order could match,
    /// objections about the balance, and a stale order.
    @ViewBuilder
    private var cancelLimitOrderDisclosures: some View {
        if let cancel = transaction.limitCancelContext {
            VStack(alignment: .leading, spacing: 16) {
                Text("limitSwap.cancel.explanation".localized)
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textSecondary)

                // THORChain cancels the FIRST (assets, ratio) match, never by
                // tx hash, so with identical resting orders it cannot promise
                // which closes.
                if cancel.duplicateRestingOrderCount > 0 {
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

    // MARK: - Signing

    /// True when signing must be refused outright. Only the balance verdict
    /// qualifies: everything else here is a disclosure the user is entitled
    /// to weigh.
    private var isSigningBlocked: Bool {
        transaction.limitCancelContext?.disclosures?.canAffordCancel == false
    }

    private func onSignPress() {
        guard !isSigningBlocked, isCancelStillEligible() else { return }
        if viewModel.validateSecurityScanner() {
            signAndProceed()
        }
    }

    /// Re-checks a limit-order cancel against storage right before signing.
    /// The review can sit open indefinitely, and the order can fill, expire or
    /// gain a recorded cancel meanwhile; signing would then spend a fee (and on
    /// L1 donate dust) for a memo that matches nothing. Called from both
    /// gates: `signAndProceed` is the last word, since Continue anyway goes
    /// straight to it, and `onSignPress` only gives earlier feedback.
    private func isCancelStillEligible() -> Bool {
        guard let cancel = transaction.limitCancelContext else { return true }
        switch limitOrderCancelRecheck(cancel, pubKeyECDSA: vault.pubKeyECDSA) {
        case .stillEligible, .noLocalOrder:
            // `.noLocalOrder` is allowed only because nothing better exists: a
            // device without the row has the original eligibility decision to
            // go on, and refusing would put the cancel out of its reach.
            staleOrderMessage = nil
            return true
        case .orderChanged:
            staleOrderMessage = "limitSwap.cancel.orderChanged".localized
            fastPasswordPresented = false
            return false
        case .unverifiable:
            // Nothing is known about the order, so "this order changed" would
            // be a claim that cannot be made. Refuse either way.
            staleOrderMessage = "limitSwap.cancel.unavailableVaultUnreadable".localized
            fastPasswordPresented = false
            return false
        }
    }

    private func signAndProceed() {
        guard !isSigningBlocked, isCancelStillEligible() else { return }
        Task {
            do {
                let payload = try await viewModel.createKeysignPayload(tx: transaction)
                await MainActor.run {
                    // FunctionTransaction retries show no reason banner, so the
                    // signal is not threaded back to this review.
                    let context = SigningTxContext.functionCall(vault: vault, tx: transaction, retry: SendRetrySignal())
                    let route: SigningRoute
                    if let fastPassword = fastVaultPassword.nilIfEmpty {
                        route = .keysign(.fast(context: context, keysignPayload: payload, fastVaultPassword: fastPassword))
                    } else {
                        route = .pair(context: context, keysignPayload: payload, fastVaultPassword: nil)
                    }
                    reviewPresenter.proceed(to: route, presentationID: presentationID)
                }
            } catch {
                await MainActor.run {
                    self.error = error as? HelperError
                }
            }
        }
    }
}
