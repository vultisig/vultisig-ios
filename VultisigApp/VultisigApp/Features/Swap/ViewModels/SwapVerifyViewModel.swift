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
    @ObservationIgnored private let logger = Logger(subsystem: "com.vultisig.app", category: "swap-verify")
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
    var isLoading = false
    var isLoadingFees = false
    var isLoadingTransaction = false
    var timer: Int = 59

    init(
        transaction: SwapTransaction,
        interactor: SwapInteractor = DefaultSwapInteractor.live
    ) {
        self.transaction = transaction
        self.interactor = interactor
    }

    func onLoad() {
        // SecurityScannerViewModel stays an ObservableObject (used elsewhere),
        // so we bridge its @Published `state` into our @Observable property via Combine.
        securityScannerCancellable = securityScanViewModel.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                self?.securityScannerState = state
            }
    }

    func isValidForm(shouldApprove: Bool) -> Bool {
        // Limit orders only have the "amount is correct" checkbox — fee /
        // approve checkboxes don't render for limit (no quote, no ERC20
        // approve). Mirrors the verify-screen UI gate.
        if transaction.isLimit {
            return isAmountCorrect
        }
        if shouldApprove {
            return isAmountCorrect && isFeeCorrect && isApproveCorrect
        } else {
            return isAmountCorrect && isFeeCorrect
        }
    }

    func scan() async {
        await securityScanViewModel.scan(transaction: transaction)
    }

    func validateSecurityScanner() -> Bool {
        showSecurityScannerSheet = securityScannerState.shouldShowWarning
        return !securityScannerState.shouldShowWarning
    }

    func updateTimer(vault: Vault, referredCode: String) async {
        timer -= 1
        if timer < 1 {
            await refreshData(vault: vault, referredCode: referredCode)
            timer = 59
        }
    }

    func refreshData(vault: Vault, referredCode: String) async {
        // Limit orders have no market quote to refresh — fetching one here
        // would attach a market quote to a limit transaction and break the
        // `quote == nil` limit invariant (the signed artifact is the pre-built
        // limit memo; a refreshed quote would only render misleading
        // provider/fee rows). Covers the 60s ticker and the retry path.
        guard !transaction.isLimit else { return }

        isLoadingFees = true
        defer { isLoadingFees = false }

        do {
            let result = try await interactor.fetchQuote(
                amount: transaction.fromAmount,
                fromCoin: transaction.fromCoin,
                toCoin: transaction.toCoin,
                vault: vault,
                referredCode: referredCode,
                slippageBps: transaction.advancedSettings.slippage.bps,
                recipientAddress: transaction.advancedSettings.externalRecipient
            )
            var updated = transaction
            if let result {
                updated = updated.with(
                    quote: result.quote,
                    vultDiscountBps: result.vultDiscountBps,
                    referralDiscountBps: result.referralDiscountBps
                )
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
                validationFee = updated.displayedNetworkFeeWei
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
            transaction = updated
            error = nil
        } catch {
            guard (error as? URLError)?.code != .cancelled else { return }
            logger.warning("Refresh quote error: \(error.localizedDescription)")
            self.error = error
        }
    }

    /// Sign-time fund-safety gate: delegates the live inbound re-check to the
    /// interactor (which owns the THORChain / Maya services), keeping this VM
    /// free of any chain-service dependency. Returns `true` when it's safe to
    /// sign; on a halt (or an unverifiable fetch) it sets `error` and returns
    /// `false` so the caller does NOT build the payload or navigate.
    func isSourceChainSafeToSign() async -> Bool {
        do {
            try await interactor.assertSourceChainNotHalted(transaction: transaction)
            return true
        } catch {
            self.error = error
            return false
        }
    }

    func buildSwapKeysignPayload(vault: Vault) async -> KeysignPayload? {
        isLoadingTransaction = true
        defer { isLoadingTransaction = false }

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
                    vault: vault
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
            self.error = error
            return nil
        }
    }
}
