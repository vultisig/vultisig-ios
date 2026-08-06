//
//  SendCryptoVerifyViewModel.swift
//  VultisigApp
//
//  Holds the immutable `SendTransaction` handed off from Details. The
//  transaction itself is `@Published var` so the load/refresh paths can
//  swap in an updated copy (via `with(...)`) with re-fetched gas/fee while
//  identity fields (coin, vault, toAddress, amount) stay pinned.
//

import SwiftUI
import BigInt
import WalletCore
import OSLog

@MainActor
class SendCryptoVerifyViewModel: ObservableObject {
    let securityScanViewModel = SecurityScannerViewModel()

    /// The hand-off transaction. Updated via `with(...)` on refresh.
    @Published var transaction: SendTransaction

    /// Pulled off the legacy class — now owned by the VM since the immutable
    /// struct can't carry transient UI state.
    @Published var isCalculatingFee: Bool = false
    @Published var fastVaultPassword: String = ""

    @Published var isAddressCorrect = false
    @Published var isAmountCorrect = false
    @Published var isApproveCorrect = false
    @Published var showAlert = false
    @Published var isLoading = false
    @Published var errorMessage = ""
    @Published var hasBalanceError = false

    /// Whether the last fee/amount load failed.
    ///
    /// Kept separate from `hasBalanceError`, which means "the amount doesn't fit
    /// the balance" and gates the XRP destination guards. This one means "the
    /// figures on screen were never resolved": the summary still shows whatever
    /// the Details screen handed over — for a max send after a failed refine,
    /// the optimistic full balance at a zero fee — while Sign would build and
    /// sign a fresh plan from live data the user was never shown.
    ///
    /// Sign stays disabled until a load runs to completion — only that path
    /// clears this. Clearing on load *entry* instead would let a cancelled retry
    /// release the hold with the previous failure's figures still on screen and
    /// nothing having re-resolved them. Recovery is the alert's Retry button,
    /// since `.onLoad` runs once.
    @Published var hasLoadError = false

    @Published var showSecurityScannerSheet: Bool = false
    @Published var securityScannerState: SecurityScannerState = .idle

    private let interactor: SendInteractor
    private let logic: SendCryptoVerifyLogic

    /// A keysign payload built by the calling flow that must be signed verbatim,
    /// instead of being re-derived from `transaction` on confirm. Circle USDC
    /// withdrawals rely on this: the signed tx is a native-ETH MSCA
    /// `execute(USDC, 0, transfer(vault, amount))` call whose calldata lives in
    /// `memo`, while `transaction` carries the USDC coin purely so the verify
    /// summary shows the real amount and recipient. Re-deriving from the USDC
    /// `transaction` would instead sign `transfer(MSCA, 0)` — a no-op.
    private let prebuiltKeysignPayload: KeysignPayload?

    /// Exposes the pre-built payload to the verify summary so it can surface
    /// payload-only context the display `transaction` doesn't carry — e.g. the
    /// decoded sign-data (signDirect/signAmino/signSolana/…) detail rows.
    var verifyKeysignPayload: KeysignPayload? { prebuiltKeysignPayload }

    /// Whether the pre-built payload bundles an ERC-20 `approve` that will be
    /// signed and broadcast before the main transaction (a first-time
    /// allowance-gated deposit). Drives the extra confirmation checkbox on the verify screen,
    /// mirroring the swap approve flow.
    var isApproveRequired: Bool { prebuiltKeysignPayload?.approvePayload != nil }

    /// Fiat value of the send amount for the verify header — the same price
    /// source and empty-on-edge-case semantics as the co-sign summary
    /// (`CryptoAmountFormatter.amountInFiat`): empty for a zero amount or when
    /// no rate is available, never a misleading "$0.00". Derived live from the
    /// coin's current rate rather than the Details screen's `amountInFiat`
    /// input text, which is unformatted (no currency symbol), truncated typing
    /// state. Independent of the fee calculation, so it stays visible while
    /// `isCalculatingFee` blurs the fee row; a max-send amount adjustment
    /// republishes `transaction` and recomputes this along with it.
    var amountFiat: String {
        CryptoAmountFormatter.amountInFiat(coin: transaction.coin, amount: transaction.amountDecimal)
    }

    init(
        transaction: SendTransaction,
        interactor: SendInteractor = DefaultSendInteractor.live,
        prebuiltKeysignPayload: KeysignPayload? = nil,
        rippleService: RippleService = .shared
    ) {
        self.transaction = transaction
        self.interactor = interactor
        self.logic = SendCryptoVerifyLogic(interactor: interactor, rippleService: rippleService)
        self.prebuiltKeysignPayload = prebuiltKeysignPayload
    }

    func onLoad() {
        securityScanViewModel.$state
            .assign(to: &$securityScannerState)
    }

    func loadGasInfoForSending() async {
        isCalculatingFee = true
        isLoading = true
        errorMessage = ""
        hasBalanceError = false
        // `hasLoadError` is deliberately NOT cleared here. Clearing on entry
        // would let a *cancelled* retry release the hold: the previous failure's
        // figures would still be on screen, with nothing having re-resolved them.
        // Only a load that runs to completion clears it.

        // Ensure balance is loaded before validation (protects against stale/empty balances)
        await interactor.updateBalance(for: transaction.coin)

        // For non-native tokens, also update native token balance (needed for gas validation)
        if !transaction.coin.isNativeToken {
            if let nativeToken = transaction.vault.coins.nativeCoin(chain: transaction.coin.chain) {
                await interactor.updateBalance(for: nativeToken)
            }
        }

        do {
            let feeResult = try await resolveFee()

            var newAmount = transaction.amount
            // Adjust amount for max send if fee changed (only for native tokens where fee is deducted from balance)
            if transaction.sendMaxAmount, transaction.coin.isNativeToken,
               let plannedRaw = feeResult.maxSendAmountRaw {
                // UTXO max: the plan this fee came from already says exactly what
                // the recipient will get. Re-deriving `balance − fee` here would
                // show a figure the signer does not produce whenever the input
                // selection excluded an output.
                if plannedRaw > 0 {
                    newAmount = SendCryptoLogic.formatRawAmount(plannedRaw, coin: transaction.coin)
                }
            } else if transaction.sendMaxAmount && transaction.coin.isNativeToken {
                // `balance − fee − ED`. The ED reservation lets a DOT max-send
                // settle at `balance − fee − ED` (`transfer_keep_alive` rejects
                // a transfer that would reap the sender); zero for non-ED chains
                // — including TAO (`transfer_allow_death`) and XRP, whose
                // rawBalance is already reserve-net. Terra Classic additionally
                // clamps to the Details amount so the refetched fee's embedded
                // burn tax can't push the re-derived amount past the tax fixed
                // point and underfund the send.
                let candidate = SendCryptoLogic.verifyMaxCandidateRaw(
                    coin: transaction.coin,
                    fee: feeResult.fee,
                    previousAmountRaw: transaction.amountInRaw
                )
                if candidate > 0 {
                    let decimals = transaction.coin.decimals
                    let amountDecimal = Decimal(string: String(candidate)) ?? 0
                    let formattedAmount = amountDecimal / pow(10, decimals)
                    newAmount = "\(formattedAmount)"
                }
            }

            transaction = transaction.with(
                gas: feeResult.gas,
                fee: feeResult.fee
            )
            if newAmount != transaction.amount {
                transaction = transaction.copy(amount: newAmount)
            }

            isCalculatingFee = false

            validateBalanceWithFee()
            // Keep isLoading true across the async destination guard so Sign
            // stays disabled until the load-time validation fully settles —
            // otherwise Sign briefly re-enables while account_info is in flight.
            try await validateDestinationActivationIfNeeded()
            // The figures on screen have now been resolved end to end, so a
            // previous failure's hold is released. Reached only on the success
            // path: a throw or a cancellation leaves the hold as it was.
            hasLoadError = false
            isLoading = false
        } catch is CancellationError {
            // The load pass was cancelled/superseded. Abort quietly — don't
            // flag an error and don't mark the load complete; just release the
            // transient flags. Cancellation propagates here instead of being
            // swallowed mid-guard, so a cancelled load doesn't read as success.
            isCalculatingFee = false
            isLoading = false
        } catch {
            Log.send.viewModel.error("Error calculating fee: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
            showAlert = true
            // The amount and fee on screen were never resolved against the
            // chain. Signing from here would build a fresh plan the user has not
            // seen, so hold Sign until a load succeeds.
            hasLoadError = true
            isCalculatingFee = false
            isLoading = false
        }
    }

    /// The fee the summary shows.
    ///
    /// A flow that pre-built its payload signs those bytes verbatim, so the fee
    /// it will be charged is the one recorded on the payload — not one
    /// re-estimated from `transaction`, which is a display-only stand-in whose
    /// coin, amount and destination exist to make the summary read correctly.
    /// For Kamino the two genuinely differ: the signed bytes carry an injected
    /// ComputeBudget pair that a fresh estimate of a plain Solana transfer knows
    /// nothing about.
    ///
    /// Falls back to the estimate when the payload records no usable fee, so a
    /// pre-built flow that never carried one is no worse off than before.
    private func resolveFee() async throws -> SendCryptoVerifyLogic.FeeResult {
        if let prebuiltKeysignPayload, let fee = PrebuiltPayloadFee.fee(for: prebuiltKeysignPayload) {
            return SendCryptoVerifyLogic.FeeResult(fee: fee, gas: fee)
        }
        return try await logic.calculateFee(tx: transaction)
    }

    /// Load-time destination-activation guard. XRPL rejects a Payment that
    /// would create the destination account with less than the base reserve
    /// (`tecNO_DST_INSUF_XRP`) — on-chain, after the ceremony, with the fee
    /// burned. Run it in the same load pass as the amount/balance checks so an
    /// unfunded sub-reserve destination shows the error and disables Sign on
    /// load, not only when Sign is tapped. No-op for every non-XRP send (the
    /// logic guards on the chain, so nothing hits the network) and for
    /// pre-built-payload flows; skipped when a balance error already owns the
    /// alert so the two guards don't stack.
    private func validateDestinationActivationIfNeeded() async throws {
        guard prebuiltKeysignPayload == nil, !hasBalanceError else { return }
        do {
            try await logic.validateDestinationIfNeeded(tx: transaction)
            // Issued-currency counterpart: a token Payment to an account with no
            // trust line for that currency fails on-ledger after the ceremony.
            // Same load pass, same fail-open posture.
            try await logic.validateDestinationTrustLineIfNeeded(tx: transaction)
            // A TrustSet must be able to afford the owner reserve it locks up.
            // Re-checked here against the freshly loaded balance and fee, not
            // just when the activation sheet quoted it.
            try await logic.validateTrustLineReserveIfNeeded(tx: transaction)
        } catch is CancellationError {
            // Propagate — a cancelled load must abort the whole load pass (its
            // caller returns without running post-load work), not be swallowed
            // here and not become a spurious balance error.
            throw CancellationError()
        } catch {
            errorMessage = error.localizedDescription
            showAlert = true
            isAmountCorrect = false
            hasBalanceError = true
        }
    }

    func validateBalanceWithFee() {
        // A flow that pre-built its keysign payload (e.g. Circle withdraw)
        // validates the user's amount against the real source balance upstream
        // (the MSCA's USDC balance), and `transaction` here carries a display-only
        // USDC coin whose `rawBalance` is the vault EOA (~0). Running the standard
        // balance check would wrongly trip `walletBalanceExceededError` and disable
        // signing, so skip it — mirrors the Tron-staking skip in the logic.
        guard prebuiltKeysignPayload == nil else { return }

        let result = logic.validateBalanceWithFee(tx: transaction)
        if !result.isValid {
            errorMessage = result.errorMessage ?? ""
            showAlert = true
            isAmountCorrect = false
            hasBalanceError = true
        }
    }

    /// A Kamino transaction whose decoded bytes contradict this screen, or which
    /// cannot be decoded at all, must not be signed.
    ///
    /// The decode is the only independent account of what the bytes do, so if it
    /// disagrees with the summary above it, one of the two is wrong and nobody
    /// looking at the screen can tell which. Rendering the contradiction and
    /// leaving Sign enabled would make the check advisory, which is the posture
    /// this whole feature was built to avoid. `nil` payload and every non-Kamino
    /// payload resolve to `.notKamino`, which blocks nothing.
    var isKaminoDecodeRefused: Bool {
        KaminoVerifyPresentation.state(for: prebuiltKeysignPayload).blocksSigning
    }

    var isValidForm: Bool {
        if isApproveRequired {
            return isAddressCorrect && isAmountCorrect && isApproveCorrect
        }
        return isAddressCorrect && isAmountCorrect
    }

    var signButtonDisabled: Bool {
        // `hasLoadError` and `isKaminoDecodeRefused` are independent fail-closed
        // holds on the same button — the figures were never resolved, and the
        // bytes contradict the figures. Either one alone must block Sign, so
        // they compose rather than replace each other.
        !isValidForm || isLoading || hasBalanceError || hasLoadError || isKaminoDecodeRefused
    }

    func validateForm() async throws -> KeysignPayload {
        isLoading = true
        defer { isLoading = false }

        if !isValidForm {
            throw HelperError.runtimeError("mustAgreeTermsError")
        }

        // Re-checked here rather than trusted from the button. The button state
        // is a rendering; this is the seam every signature passes through.
        if isKaminoDecodeRefused {
            throw HelperError.runtimeError("kaminoVerifyRefused".localized)
        }

        // A flow that pre-built its keysign payload (e.g. Circle withdraw) must
        // sign it verbatim. Re-deriving from `transaction` here would change the
        // signed tx, so confirm against the pre-built payload directly.
        if let prebuiltKeysignPayload {
            return prebuiltKeysignPayload
        }

        try await logic.validateDestinationIfNeeded(tx: transaction)
        try await logic.validateDestinationTrustLineIfNeeded(tx: transaction)
        try await logic.validateTrustLineReserveIfNeeded(tx: transaction)
        try await logic.validateUtxosIfNeeded(tx: transaction)
        let keysignPayload = try await logic.buildKeysignPayload(tx: transaction, vault: transaction.vault)
        return keysignPayload
    }

    func scan() async {
        await securityScanViewModel.scan(transaction: transaction)
    }

    func validateSecurityScanner() -> Bool {
        showSecurityScannerSheet = securityScannerState.shouldShowWarning
        return !securityScannerState.shouldShowWarning
    }
}
