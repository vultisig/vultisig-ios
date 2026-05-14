//
//  SendDetailsViewModel.swift
//  VultisigApp
//
//  Form-state-on-VM rewrite of the Send Details screen. Owns every form
//  field directly (replacing the legacy `FunctionCallForm`'s
//  `@Published` fields) and produces an immutable `SendTransaction` only
//  on Continue via `makeTransaction()`. Async work goes through
//  `SendInteractor` so tests can inject a mock.
//
//  Temporary name during the form-VM rewrite split: this class will be
//  renamed to `SendDetailsViewModel` in the follow-up PR that deletes
//  the existing UI-state-only `SendDetailsViewModel` and rewires
//  `SendDetailsScreen` + the `SendDetails*` components to bind to it.
//

import BigInt
import Foundation
import Mediator
import OSLog
import SwiftUI
import VultisigCommonData

enum SendDetailsFocusedTab: String {
    case asset
    case address
    case amount
}

@MainActor
@Observable
final class SendDetailsViewModel {
    @ObservationIgnored private let logger = Logger(subsystem: "com.vultisig.app", category: "send-details-form-vm")
    @ObservationIgnored private let interactor: SendInteractor

    // MARK: - Identity (immutable once set)
    let vault: Vault
    let hasPreselectedCoin: Bool

    // MARK: - UI state (merged from the deleted UI-only SendDetailsViewModel)
    var selectedChain: Chain? = nil
    private(set) var selectedTab: SendDetailsFocusedTab?
    var assetSetupDone: Bool = false
    var addressSetupDone: Bool = false
    var amountSetupDone: Bool = false
    var showCoinPickerSheet: Bool = false
    var showChainPickerSheet: Bool = false

    // MARK: - Form fields
    var coin: Coin
    var fromAddress: String
    var toAddress: String = ""
    var toAddressLabel: String? = nil
    var amount: String = ""
    var amountInFiat: String = ""
    var memo: String = ""
    var feeMode: FeeMode = .default
    var sendMaxAmount: Bool = false
    var isFastVault: Bool = false
    var isStakingOperation: Bool = false
    var transactionType: VSTransactionType = .unspecified
    var memoFunctionDictionary: [String: String] = [:]
    var wasmContractPayload: WasmExecuteContractPayload? = nil

    // MARK: - Fee / gas (derived from interactor calls)
    var gas: BigInt = .zero
    var fee: BigInt = .zero
    var estimatedGasLimit: BigInt? = nil
    var customGasLimit: BigInt? = nil
    var customByteFee: BigInt? = nil

    // MARK: - VM state (replaces `FunctionCallForm.isCalculatingFee` etc.)
    var isLoading: Bool = false
    var isValidatingForm: Bool = false
    var isCalculatingFee: Bool = false
    var isAddressResolved: Bool? = nil
    var errorTitle: String = ""
    var errorMessage: String? = nil
    var showAlert: Bool = false
    var showAddressAlert: Bool = false
    var showAmountAlert: Bool = false

    // MARK: - Address-resolution + form-validity flags

    /// Whether the most recent `validateToAddress()` succeeded. Mirrors
    /// `isNamespaceResolved` on the legacy `SendCryptoViewModel` — used by
    /// the screen to gate tab-transitions after ENS/TNS resolution.
    var isNamespaceResolved: Bool = false

    /// Whether the form passed validation. The legacy class kept this as a
    /// separate flag from `validateForm()`'s return value so SwiftUI bindings
    /// could observe it.
    var isValidForm: Bool = true

    // MARK: - Pending transaction state (Cosmos chains)
    var hasPendingTransaction: Bool = false
    var pendingTransactionCountdown: Int = 0
    var isCheckingPendingTransactions: Bool = false

    // MARK: - Cancellation
    @ObservationIgnored private var addressResolutionTask: Task<Void, Never>?

    // MARK: - Init

    init(
        coin: Coin,
        vault: Vault,
        hasPreselectedCoin: Bool = false,
        interactor: SendInteractor = DefaultSendInteractor.live
    ) {
        self.coin = coin
        self.vault = vault
        self.hasPreselectedCoin = hasPreselectedCoin
        self.fromAddress = coin.address
        self.interactor = interactor
    }

    // MARK: - UI flow (moved from the old UI-only SendDetailsViewModel)

    /// Initial tab selection. If a coin was pre-selected (e.g., entered the
    /// flow from a specific coin's detail screen), skip the asset tab and
    /// jump straight to the address step.
    func onLoad() {
        if hasPreselectedCoin {
            assetSetupDone = true
            selectedTab = .address
        } else {
            selectedTab = .asset
        }
    }

    func onSelect(tab: SendDetailsFocusedTab) {
        switch tab {
        case .asset, .address:
            selectedTab = tab
        case .amount:
            guard addressSetupDone else { return }
            selectedTab = tab
        }
    }

    /// Detects the chain from a scanned/pasted address and switches the form
    /// to the detected chain's native coin (if the vault has it). Used by the
    /// QR scanner sheet on Details.
    func detectAndSwitchChain(from address: String, currentChain: Chain) -> Coin? {
        guard let detectedChain = AddressService.detectChain(from: address, vault: vault, currentChain: currentChain) else {
            return nil
        }
        guard let detectedCoin = vault.coins.first(where: { $0.chain == detectedChain && $0.isNativeToken }) else {
            return nil
        }
        selectedChain = detectedChain
        coin = detectedCoin
        fromAddress = detectedCoin.address
        return detectedCoin
    }

    // MARK: - Derived state

    /// Continue button is disabled while either async path is running.
    var continueButtonDisabled: Bool {
        isLoading || isValidatingForm
    }

    /// Mirrors `SendCryptoViewModel.showLoader` — the legacy screen shows the
    /// loader overlay only while form validation is running, not for the
    /// shorter async checks (fee fetch, etc).
    var showLoader: Bool {
        isValidatingForm
    }

    /// The native coin used to pay gas — `self.coin` for native sends, the
    /// EVM-native sibling otherwise. Mirrors `SendTransaction.feeCoin`.
    var feeCoin: Coin {
        SendTransaction.resolveFeeCoin(coin: coin, vault: vault)
    }

    var gasLimit: BigInt {
        customGasLimit ?? estimatedGasLimit ?? BigInt(EVMHelper.defaultETHTransferGasUnit)
    }

    var byteFee: BigInt {
        customByteFee ?? gas
    }

    var amountInRaw: BigInt {
        SendCryptoLogic.amountInRaw(coin: coin, amount: amount)
    }

    var amountDecimal: Decimal {
        SendCryptoLogic.amountDecimal(coin: coin, amount: amount)
    }

    var isDeposit: Bool {
        SendCryptoLogic.isDeposit(coin: coin, memoFunctionDictionary: memoFunctionDictionary)
    }

    var gasInReadable: String {
        SendCryptoLogic.gasInReadable(coin: coin, gasNativeCoin: feeCoin, gas: gas, fee: fee)
    }

    // MARK: - Pending transaction state

    /// Mirrors the legacy `initializePendingTransactionState(for:)` — flagged on
    /// for Cosmos chains so the UI can show a countdown, off otherwise.
    func initializePendingTransactionState(for chain: Chain) {
        if chain.supportsPendingTransactions {
            isCheckingPendingTransactions = true
        } else {
            isCheckingPendingTransactions = false
            hasPendingTransaction = false
            pendingTransactionCountdown = 0
        }
    }

    @ObservationIgnored private var countdownTask: Task<Void, Never>?

    /// Synchronously inspect the pending-transaction manager and update VM
    /// state. Starts polling + the 1s countdown loop when a pending tx is
    /// found; stops everything when none. Call this from `.onAppear` and on
    /// every `viewModel.coin` change.
    func refreshPendingTransactionState() {
        guard coin.chain.supportsPendingTransactions else {
            hasPendingTransaction = false
            pendingTransactionCountdown = 0
            isCheckingPendingTransactions = false
            stopCountdownTask()
            return
        }

        isCheckingPendingTransactions = true
        let manager = PendingTransactionManager.shared
        let hasPending = manager.hasPendingTransactions(for: coin.address, chain: coin.chain)

        if hasPending {
            hasPendingTransaction = true
            isCheckingPendingTransactions = false
            startCountdownTask()
            manager.startPollingForChain(coin.chain)
        } else {
            hasPendingTransaction = false
            pendingTransactionCountdown = 0
            isCheckingPendingTransactions = false
            stopCountdownTask()
            manager.stopPollingForChain(coin.chain)
        }
    }

    /// User-driven refresh — pulls the pending-tx manager and re-evaluates.
    func forceCheckPendingTransactions() async {
        await PendingTransactionManager.shared.forceCheckPendingTransactions()
        refreshPendingTransactionState()
    }

    /// Called when the user navigates away from the form. Stops polling for
    /// the *current* coin's chain and tears down the countdown.
    func tearDownPendingTransactionState() {
        PendingTransactionManager.shared.stopAllPolling()
        stopCountdownTask()
    }

    /// Recomputes `pendingTransactionCountdown` from the oldest pending tx.
    /// Exposed so the countdown Task can call it on every 1s tick; tests can
    /// also call it directly to assert the count math without a real timer.
    func updateCountdownTick() {
        guard coin.chain.supportsPendingTransactions else { return }

        let manager = PendingTransactionManager.shared
        if let oldest = manager.getOldestPendingTransaction(for: coin.address, chain: coin.chain) {
            pendingTransactionCountdown = Int(Date().timeIntervalSince(oldest.timestamp))
            hasPendingTransaction = true
        } else {
            hasPendingTransaction = false
            pendingTransactionCountdown = 0
            stopCountdownTask()
        }
    }

    private func startCountdownTask() {
        stopCountdownTask()
        countdownTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                await MainActor.run { self?.updateCountdownTick() }
            }
        }
    }

    private func stopCountdownTask() {
        countdownTask?.cancel()
        countdownTask = nil
    }

    // MARK: - Fast vault

    /// Decision 2 win: vault is non-optional, so no singleton lookup.
    /// Decision: use `hasPrefix("server-")` for local-party check (Phase D
    /// lesson) — the interactor's `loadFastVault(vault:)` already does this.
    func loadFastVault() async {
        isFastVault = await interactor.loadFastVault(vault: vault)
    }

    // MARK: - Address resolution

    /// Debounced (1s) ENS/TNS resolution. Cancels in-flight requests on new
    /// input. Phase D lesson: address resolution and fee fetch are serialized
    /// — `validateToAddress` must complete before any `loadGasInfo` call.
    func debouncedResolveAddress() {
        addressResolutionTask?.cancel()
        isAddressResolved = nil
        addressResolutionTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, !Task.isCancelled else { return }
            isAddressResolved = await validateToAddress()
        }
    }

    func cancelAddressResolution() {
        addressResolutionTask?.cancel()
        isAddressResolved = nil
    }

    // Returns true if the address is valid for the current coin's chain.
    // `async` reserves the seam for an ENS/TNS resolver injection in a
    // follow-up — `validateToAddress` semantically belongs in the async
    // validation pipeline next to `validateForm`.
    // swiftlint:disable:next async_without_await
    func validateToAddress() async -> Bool {
        guard !toAddress.isEmpty else { return false }
        return AddressService.validateAddress(address: toAddress, chain: coin.chain)
    }

    func isValidAddressFormat() -> Bool {
        guard !toAddress.isEmpty else { return false }
        let isValid = AddressService.validateAddress(address: toAddress, chain: coin.chain)
        if isValid {
            showAddressAlert = false
            errorMessage = nil
        }
        return isValid
    }

    // MARK: - Fiat / crypto conversion

    /// Convert a fiat-typed value to the equivalent coin amount. Mirrors
    /// `LegacySendCryptoInteractor.convertFiatToCoin`. Phase D lesson: empty
    /// input clears `amount` instead of leaving a stale value.
    func convertFiatToCoin(newValue: String) {
        let newValueDecimal = newValue.toDecimal()
        guard newValueDecimal > 0, coin.price > 0 else {
            amount = ""
            return
        }
        let newValueCoin = newValueDecimal / Decimal(coin.price)
        let truncated = newValueCoin.truncated(toPlaces: coin.decimals)
        amount = truncated.formatToDecimal(digits: coin.decimals)
        sendMaxAmount = false
        amountInFiat = newValue
    }

    /// Convert a coin-typed value to its fiat equivalent. `setMaxValue` mirrors
    /// the legacy flag — when true, this update is from the max-amount path
    /// and shouldn't reset the sendMaxAmount flag.
    func convertToFiat(newValue: String, setMaxValue: Bool = false) {
        let newValueDecimal = newValue.toDecimal()
        guard newValueDecimal > 0 else {
            amountInFiat = ""
            sendMaxAmount = setMaxValue ? sendMaxAmount : false
            return
        }
        let newValueFiat = newValueDecimal * Decimal(coin.price)
        let truncated = newValueFiat.truncated(toPlaces: 2)
        amountInFiat = truncated.formatToDecimal(digits: coin.decimals)
        sendMaxAmount = setMaxValue
        amount = newValue
    }

    // MARK: - Max amount

    /// Per-chain max-amount calculation. Delegates the on-chain fetch to
    /// `interactor.fetchGasAndFee`; max-amount math sits in `SendCryptoLogic`.
    /// Non-native sources see their gas paid in the chain's native sibling,
    /// so the deductible fee here is `.zero` for ERC20 / SPL / etc.
    func setMaxAmount(percentage: Double = 100) async {
        errorMessage = ""
        isLoading = true
        defer { isLoading = false }

        let maxFee: BigInt
        do {
            let result = try await interactor.fetchGasAndFee(
                coin: coin,
                toAddress: toAddress.isEmpty ? coin.address : toAddress,
                amount: .zero,
                memo: memo.isEmpty ? nil : memo,
                sendMaxAmount: percentage == 100,
                isDeposit: isDeposit,
                transactionType: transactionType,
                gasLimit: gasLimit,
                feeMode: feeMode,
                fromAddress: fromAddress
            )
            maxFee = coin.isNativeToken ? result.fee : .zero
        } catch {
            logger.error("setMaxAmount failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
            return
        }

        sendMaxAmount = percentage == 100
        let maxAmount = SendCryptoLogic.computeMaxAmount(coin: coin, fee: maxFee)
        amount = percentage == 100
            ? maxAmount
            : SendCryptoLogic.applyPercentage(maxAmount: maxAmount, percentage: percentage, coinDecimals: coin.decimals)
        convertToFiat(newValue: amount, setMaxValue: sendMaxAmount)
    }

    // MARK: - Fee / gas refresh

    /// Re-fetches gas + fee for the current form state, **threading `feeMode`
    /// end-to-end** (regression target for the feeMode bug fix). Preserves
    /// `customGasLimit` / `customByteFee` so user-pinned values survive refresh.
    func loadGasInfo() async {
        // Phase D lesson — zero-amount state reset.
        if amount.isEmpty || amount.toDecimal().isZero {
            gas = .zero
            fee = .zero
            estimatedGasLimit = nil
            isCalculatingFee = false
            return
        }

        isCalculatingFee = true
        defer { isCalculatingFee = false }

        do {
            let result = try await interactor.fetchGasAndFee(
                coin: coin,
                toAddress: toAddress,
                amount: amountInRaw,
                memo: memo.isEmpty ? nil : memo,
                sendMaxAmount: sendMaxAmount,
                isDeposit: isDeposit,
                transactionType: transactionType,
                gasLimit: gasLimit,
                feeMode: feeMode,
                fromAddress: fromAddress
            )
            gas = result.gas
            fee = result.fee
        } catch {
            logger.error("loadGasInfo failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Amount validation (sync, format-only)

    /// Synchronous decimal-format check. Used by the amount-tab onChange to
    /// give immediate feedback while the user types, separate from the
    /// async `validateForm()` that runs on Continue.
    func validateAmount(_ candidate: String) {
        errorTitle = ""
        errorMessage = nil
        isValidForm = candidate.isValidDecimal()
        if !isValidForm {
            errorTitle = "error"
            errorMessage = "decimalAmountError".localized
            showAlert = true
        }
    }

    // MARK: - Mediator lifecycle

    /// Stops the keysign Mediator service when leaving the Send flow.
    /// Mirrors `SendCryptoViewModel.stopMediator` — kept here so the screen
    /// can call it from `.onDisappear`.
    func stopMediator() {
        Mediator.shared.stop()
        logger.info("mediator server stopped.")
    }

    // MARK: - Form validation

    // Async form validation. Mirrors the legacy `validateForm` but reads
    // VM state directly. Returns true iff every check passes. `async`
    // reserved for future address-resolver awaits (ENS/TNS).
    // swiftlint:disable:next async_without_await
    func validateForm() async -> Bool {
        resetStates()
        isValidatingForm = true
        defer {
            isValidatingForm = false
            isLoading = false
        }

        // Cosmos pending-tx blocker.
        if hasPendingTransaction && coin.chain.supportsPendingTransactions {
            errorTitle = "error"
            errorMessage = "pendingTransactionError"
            showAlert = true
            return false
        }

        // TRON staking short-circuit (legacy parity).
        let isTronStaking = coin.chain == .tron && isStakingOperation

        // Zero amount.
        if amount.isEmpty || amountDecimal.isZero {
            errorTitle = "error"
            errorMessage = "positiveAmountError"
            showAmountAlert = true
            return false
        }

        // Address format.
        guard isValidAddressFormat() else {
            errorTitle = "error"
            errorMessage = "invalidAddressError"
            showAddressAlert = true
            return false
        }

        // Balance check.
        if !isTronStaking {
            let exceeded = SendCryptoLogic.isAmountExceeded(
                coin: coin,
                amount: amount,
                sendMaxAmount: sendMaxAmount,
                fee: fee,
                gas: gas,
                isStakingOperation: isStakingOperation
            )
            if exceeded {
                errorTitle = "error"
                errorMessage = "walletBalanceExceededError"
                showAmountAlert = true
                return false
            }
            // ERC20 gas balance check.
            if !coin.isNativeToken, let nativeToken = vault.coins.nativeCoin(chain: coin.chain) {
                let nativeBalance = nativeToken.rawBalance.toBigInt(decimals: nativeToken.decimals)
                if fee > nativeBalance {
                    errorTitle = "error"
                    errorMessage = String(format: "insufficientGasTokenError".localized, nativeToken.ticker, coin.ticker)
                    showAlert = true
                    return false
                }
            }
        }

        return true
    }

    // MARK: - Hand-off

    /// Construct the immutable `SendTransaction` for hand-off to Verify. Only
    /// called from the Continue button after `validateForm()` returns true.
    /// Throws if validation fails so the caller doesn't navigate on bad state.
    enum MakeTransactionError: LocalizedError {
        case invalidForm

        var errorDescription: String? {
            switch self {
            case .invalidForm: return "Cannot construct transaction: form has validation errors."
            }
        }
    }

    func makeTransaction() throws -> SendTransaction {
        guard amount.isValidDecimal(), !toAddress.isEmpty, !amountDecimal.isZero else {
            throw MakeTransactionError.invalidForm
        }
        return SendTransaction(
            coin: coin,
            vault: vault,
            fromAddress: fromAddress,
            toAddress: toAddress,
            toAddressLabel: toAddressLabel,
            amount: amount,
            amountInFiat: amountInFiat,
            memo: memo,
            gas: gas,
            fee: fee,
            feeMode: feeMode,
            estimatedGasLimit: estimatedGasLimit,
            customGasLimit: customGasLimit,
            customByteFee: customByteFee,
            sendMaxAmount: sendMaxAmount,
            isFastVault: isFastVault,
            isStakingOperation: isStakingOperation,
            transactionType: transactionType,
            memoFunctionDictionary: memoFunctionDictionary,
            wasmContractPayload: wasmContractPayload,
            feeCoin: feeCoin
        )
    }

    // MARK: - Reset

    /// Clear validation state ahead of an async check (matches legacy parity).
    private func resetStates() {
        errorTitle = ""
        errorMessage = nil
        isLoading = true
        showAddressAlert = false
        showAmountAlert = false
        showAlert = false
    }

    /// Reset the form for a fresh send (e.g., after Done → back to Details).
    /// Replaces the legacy `tx.reset(coin:)` that #4347 removed from the Done
    /// screen. Phase D lesson: clear *every* derived field, not just amount.
    func reset(to newCoin: Coin) {
        coin = newCoin
        fromAddress = newCoin.address
        toAddress = ""
        toAddressLabel = nil
        amount = ""
        amountInFiat = ""
        memo = ""
        feeMode = .default
        sendMaxAmount = false
        isStakingOperation = false
        transactionType = .unspecified
        memoFunctionDictionary = [:]
        wasmContractPayload = nil
        gas = .zero
        fee = .zero
        estimatedGasLimit = nil
        customGasLimit = nil
        customByteFee = nil
        isCalculatingFee = false
        errorTitle = ""
        errorMessage = nil
        showAlert = false
        showAddressAlert = false
        showAmountAlert = false
    }
}
