//
//  SwapVerifyViewModel.swift
//  VultisigApp
//
//  Holds the immutable `SwapTransaction` handed off by SwapDetailsViewModel.
//  The transaction itself is `var` so the 60s refresh path can swap in an
//  updated copy with the latest quote/fees — fields like fromCoin/toCoin/
//  fromAmount stay pinned, but the price-sensitive parts re-fetch.
//

import BigInt
import Combine
import OSLog
import SwiftUI

@MainActor
@Observable
final class SwapVerifyViewModel {
    @ObservationIgnored private let logger = Log.swap.other
    @ObservationIgnored private let interactor: SwapInteractor
    @ObservationIgnored private let securityScanViewModel = SecurityScannerViewModel()
    @ObservationIgnored private var securityScannerCancellable: AnyCancellable?

    var transaction: SwapTransaction

    var isAmountCorrect = false
    var isFeeCorrect = false
    var isApproveCorrect = false

    var showSecurityScannerSheet: Bool = false
    var securityScannerState: SecurityScannerState = .idle

    var error: Error?
    /// Set when the refresh substituted the picked route; the screen clears it.
    var routeSelectionNotice: String?
    var isLoading = false
    var isLoadingFees = false
    var isSolanaFeeResolved = true
    private(set) var isPreparingSigning = false
    var timer: Int = 59

    init(
        transaction: SwapTransaction,
        interactor: SwapInteractor? = nil
    ) {
        self.transaction = transaction
        // Resolved here rather than as a default argument, which is evaluated
        // outside the main actor that `DefaultSwapInteractor` is isolated to.
        self.interactor = interactor ?? DefaultSwapInteractor.live
    }

    func onLoad() {
        // SecurityScannerViewModel stays an ObservableObject (used elsewhere),
        // so we bridge its @Published `state` into our @Observable property via Combine.
        // It publishes on MainActor. Deliver synchronously so scan completion
        // cannot overtake a queued scanning state and restart the artwork.
        securityScannerCancellable = securityScanViewModel.$state
            .sink { [weak self] state in
                self?.securityScannerState = state
            }
    }

    func isValidForm(shouldApprove: Bool) -> Bool {
        // Every order confirms amount + network fee — both checkboxes always
        // render (a limit order surfaces its estimated source-chain fee too). A
        // bundled ERC20 approve additionally gates on the approve checkbox.
        // `shouldApprove` is `transaction.signsApprove`: the approval decided on
        // the way into Verify, for market, limit and secured-mint alike.
        if shouldApprove {
            return isAmountCorrect && isFeeCorrect && isApproveCorrect
        }
        return isAmountCorrect && isFeeCorrect
    }

    func scan() async {
        await securityScanViewModel.scan(transaction: transaction)
    }

    func validateSecurityScanner() -> Bool {
        showSecurityScannerSheet = securityScannerState.shouldShowWarning
        return !securityScannerState.shouldShowWarning
    }

    func updateTimer(vault: Vault) async {
        guard !transaction.isLimit, !isLoadingFees, !isPreparingSigning else { return }
        timer -= 1
        if timer < 1 {
            await refreshData(vault: vault)
            timer = 59
        }
    }

    func refreshData(vault: Vault) async {
        // Limit orders have no market quote to refresh — fetching one here
        // would attach a market quote to a limit transaction and break the
        // `quote == nil` limit invariant (the signed artifact is the pre-built
        // limit memo; a refreshed quote would only render misleading
        // provider/fee rows). Covers the 60s ticker and the retry path.
        guard !transaction.isLimit, !isLoadingFees, !isPreparingSigning else { return }

        isLoadingFees = true
        defer { isLoadingFees = false }

        do {
            var updated = transaction
            // Applied to the UI only once the refreshed transaction commits below.
            var routeWasSubstituted = false
            // Same-underlying secured mint has no pool quote to refresh — keep the
            // synthetic ~1:1 quote and refresh only the L1 deposit gas below.
            if transaction.mode == .standard {
                let result = try await interactor.fetchQuote(
                    amount: transaction.fromAmount,
                    fromCoin: transaction.fromCoin,
                    toCoin: transaction.toCoin,
                    vault: vault,
                    referredCode: vault.referredCode?.code ?? .empty,
                    slippageBps: transaction.advancedSettings.slippage.bps,
                    recipientAddress: transaction.advancedSettings.externalRecipient
                )
                if let result {
                    // Installing `result.quote` unconditionally would hand the user
                    // a route they never chose, immediately before signing.
                    var refreshedQuote = result.quote
                    if let picked = updated.selectedProvider {
                        if let stillOffered = result.allQuotes.first(where: { $0.provider(fromChain: updated.fromCoin.chain) == picked }) {
                            refreshedQuote = stillOffered
                        } else {
                            updated.selectedProvider = nil
                            routeWasSubstituted = true
                        }
                    }
                    updated = updated.with(
                        quote: refreshedQuote,
                        vultDiscountBps: result.vultDiscountBps,
                        referralDiscountBps: result.referralDiscountBps
                    )
                }
            }
            if updated.fromCoin.chain == .solana,
               let transactionData = SolanaSwapNetworkFee.transactionData(quote: updated.quote) {
                isSolanaFeeResolved = false
                let rent = try await SolanaSwapNetworkFee.ataRent(transactionData: transactionData)
                updated = updated.with(solanaAtaRent: rent)
                isSolanaFeeResolved = true
            } else {
                isSolanaFeeResolved = true
            }
            // Fetch the oracle fee data BEFORE validating: for EVM aggregator/
            // SwapKit routes the node admits a transaction only when the
            // account covers the signed bond (gasLimit × maxFeePerGas + value),
            // so sufficiency must be checked against the reconciled fee, not
            // the provider's quote seed. If the oracle fetch fails, validate
            // against the quote fee exactly as before — a flaky oracle must
            // never block harder than today — and surface the fetch error
            // afterwards, preserving the previous failure behavior.
            var validationFee = updated.fee
            var chainSpecificError: Error?
            do {
                let chainSpecific = try await interactor.fetchChainSpecific(
                    fromCoin: updated.fromCoin,
                    toCoin: updated.toCoin,
                    fromAmount: updated.fromAmount,
                    quote: updated.quote
                )
                updated = updated.with(
                    gas: chainSpecific.gas,
                    gasLimit: chainSpecific.gasLimit ?? .zero,
                    thorchainFee: try await interactor.computeThorchainFee(
                        chainSpecific: chainSpecific,
                        fromCoin: updated.fromCoin,
                        fromAmount: updated.fromAmount,
                        vault: vault
                    )
                )
                validationFee = SwapCryptoLogic.fundingNetworkFee(
                    displayedFee: updated.displayedNetworkFeeWei,
                    gasEstimate: chainSpecific.gas,
                    chain: updated.fromCoin.chain
                )
            } catch {
                chainSpecificError = error
            }
            if let balanceError = SwapCryptoLogic.balanceError(
                fromCoin: updated.fromCoin,
                feeCoin: updated.feeCoin,
                fromAmount: updated.fromAmount.description,
                fee: validationFee
            ) {
                throw balanceError
            }
            if let chainSpecificError {
                throw chainSpecificError
            }
            // A refreshed quote can name a different spender (another route, a
            // rotated router). The approval shown and signed has to be the one
            // read for it, so read it again; the same spend keeps its decision.
            let refreshedSpend = SwapCryptoLogic.approvalQuery(
                fromCoin: updated.fromCoin,
                amount: updated.amountInCoinDecimal,
                quote: updated.quote
            )
            let approvalChanged = transaction.mode == .standard && refreshedSpend != transaction.approvalDecision?.query
            if approvalChanged {
                updated = updated.with(approvalDecision: try await interactor.resolveApproval(for: updated, vault: vault))
            }
            transaction = updated
            error = nil
            if approvalChanged {
                // Consent given for another spender's approve does not carry over.
                isApproveCorrect = false
            }
            if routeWasSubstituted {
                // The confirmations were given for a route that is now gone.
                isAmountCorrect = false
                isFeeCorrect = false
                isApproveCorrect = false
                routeSelectionNotice = "swapRouteUnavailableResetToAuto".localized
            }
        } catch {
            guard (error as? URLError)?.code != .cancelled else { return }
            logger.warning("Refresh quote error: \(error.localizedDescription)")
            self.error = error
        }
    }

    var canStartSigning: Bool {
        isSolanaFeeResolved && !isLoadingFees && !isPreparingSigning
            && isValidForm(shouldApprove: transaction.signsApprove)
    }

    /// A successful preparation holds refresh exclusion until the caller has
    /// synchronously navigated using this context and payload. Call
    /// `finishSigning()` in a defer around that navigation; failures release it here.
    func prepareSigning(vault: Vault, retrySignal: SwapRetrySignal) async -> (context: SigningTxContext, payload: KeysignPayload)? {
        guard canStartSigning else { return nil }
        isPreparingSigning = true
        let snapshot = transaction
        var didPrepare = false
        defer {
            if !didPrepare { finishSigning() }
        }

        do {
            try Task.checkCancellation()
            try await interactor.assertSourceChainNotHalted(transaction: snapshot)
            try Task.checkCancellation()
            guard let payload = await buildSwapKeysignPayload(transaction: snapshot, vault: vault) else { return nil }
            try Task.checkCancellation()
            let context = SigningTxContext.swap(
                vaultPubKeyECDSA: vault.pubKeyECDSA,
                transaction: snapshot,
                retry: retrySignal
            )
            error = nil
            didPrepare = true
            return (context, payload)
        } catch {
            guard !(error is CancellationError), (error as? URLError)?.code != .cancelled else { return nil }
            self.error = error
            return nil
        }
    }

    func finishSigning() {
        isPreparingSigning = false
    }

    private func buildSwapKeysignPayload(transaction: SwapTransaction, vault: Vault) async -> KeysignPayload? {
        do {
            // Limit orders take a different builder — no market quote, memo
            // is pre-built on the entry screen. Everything else (route to
            // pair → keysign → done) is shared with the market path.
            if let limitContext = transaction.limitContext {
                // Sign-time insufficient-funds re-check. The market path re-runs
                // `balanceError` on every 60s refresh, but `refreshData`
                // early-returns for limit orders (no quote to refresh) so limit
                // skipped the balance check entirely. Refresh the live source
                // balance and fail CLOSED before signing, so a balance drop while
                // the user sat on Verify is caught here rather than only surfacing
                // when the deposit is broadcast. `refreshBalanceOrThrow` rethrows
                // if the balance RPC is down — otherwise a stale cached balance
                // could pass this check while the account is actually short.
                try await interactor.refreshBalanceOrThrow(for: transaction.fromCoin)
                if transaction.feeCoin != transaction.fromCoin {
                    try await interactor.refreshBalanceOrThrow(for: transaction.feeCoin)
                }
                // HIGH tier: run the same recipient safety-net the market path
                // runs in `DefaultSwapInteractor.buildSwapKeysignPayload`, which
                // the direct limit builder would otherwise skip. Limit orders
                // never set an external recipient today, so this is a defensive
                // no-op — but it keeps the limit deposit on the same fund-safety
                // gate and fails closed if a future change ever attaches an
                // external recipient without a verifiable output target.
                try SwapRecipientVerifier.verify(transaction: transaction)
                // Fail loud on an unparseable persisted amount rather than a
                // silent `?? 0`, which would sign a 0-amount deposit.
                guard let sourceAmount = BigInt(limitContext.sourceAmount) else {
                    throw LimitSwapAssemblyError.invalidSourceAmount(limitContext.sourceAmount)
                }
                // Fast pre-check against the entry-screen fee estimate BEFORE the
                // (network) payload build: catches an obvious shortfall early and
                // keeps failing closed even if the build can't run. The fresh-fee
                // re-check below then covers a gas spike since the estimate.
                if let balanceError = SwapCryptoLogic.balanceError(
                    fromCoin: transaction.fromCoin,
                    feeCoin: transaction.feeCoin,
                    fromAmount: transaction.fromAmount.description,
                    fee: transaction.networkFeeEstimate
                ) {
                    throw balanceError
                }
                // Build so the FINAL balance check validates against the ACTUAL fee
                // that will be signed. The payload carries the fresh sign-time
                // chain-specific gas (`limitDepositChainSpecific` applied inside the
                // assembler), whereas `transaction.networkFeeEstimate` is only the
                // entry-screen estimate. Mirrors the market path, which validates
                // against the freshly-refetched fee — a gas spike while the user sat
                // on Verify must not pass a stale-lower-fee check.
                let payload = try await buildLimitSwapKeysignPayload(
                    sourceCoin: transaction.fromCoin,
                    targetCoin: transaction.toCoin,
                    sourceAmount: sourceAmount,
                    memo: limitContext.memo,
                    vault: vault,
                    approvalDecision: transaction.approvalDecision,
                    expectedToAmountDecimal: transaction.toAmountDecimal
                )
                let signTimeFee = try await SwapCryptoLogic.thorchainFee(
                    for: payload.chainSpecific,
                    fromCoin: transaction.fromCoin,
                    fromAmount: transaction.fromAmount,
                    vault: vault
                )
                if let balanceError = SwapCryptoLogic.balanceError(
                    fromCoin: transaction.fromCoin,
                    feeCoin: transaction.feeCoin,
                    fromAmount: transaction.fromAmount.description,
                    fee: signTimeFee
                ) {
                    throw balanceError
                }
                return payload
            }
            return try await interactor.buildSwapKeysignPayload(transaction: transaction, vault: vault)
        } catch {
            guard !(error is CancellationError), (error as? URLError)?.code != .cancelled else { return nil }
            self.error = error
            return nil
        }
    }
}
