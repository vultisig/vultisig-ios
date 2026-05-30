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
    @ObservationIgnored private let addressResolver: (String, Chain) async throws -> String

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
    var lastResolvedAddress: String? = nil
    var amount: String = ""
    var amountInFiat: String = ""
    var memo: String = ""
    var feeMode: FeeMode = .default
    var sendMaxAmount: Bool = false
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

    /// Background fee refine for the native-coin Max path. Exposed so the UI
    /// (and tests) can observe / await the optimistic-fill → refine settle.
    @ObservationIgnored private(set) var feeRefineTask: Task<Void, Never>?

    // MARK: - Init

    init(
        coin: Coin,
        vault: Vault,
        hasPreselectedCoin: Bool = false,
        interactor: SendInteractor = DefaultSendInteractor.live,
        addressResolver: @escaping (String, Chain) async throws -> String = AddressService.resolveInput
    ) {
        self.coin = coin
        self.vault = vault
        self.hasPreselectedCoin = hasPreselectedCoin
        self.fromAddress = coin.address
        self.interactor = interactor
        self.addressResolver = addressResolver
    }

    func hydrate(from seed: SendDetailsSeed) {
        fromAddress = seed.fromAddress
        toAddress = seed.toAddress
        toAddressLabel = seed.toAddressLabel
        lastResolvedAddress = seed.lastResolvedAddress
        amount = seed.amount
        amountInFiat = seed.amountInFiat
        memo = seed.memo
        feeMode = seed.feeMode
        sendMaxAmount = seed.sendMaxAmount
        isStakingOperation = seed.isStakingOperation
        transactionType = seed.transactionType
        memoFunctionDictionary = seed.memoFunctionDictionary
        wasmContractPayload = seed.wasmContractPayload
        gas = seed.gas
        fee = seed.fee
        estimatedGasLimit = seed.estimatedGasLimit
        customGasLimit = seed.customGasLimit
        customByteFee = seed.customByteFee
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
        customGasLimit ?? estimatedGasLimit ?? BigInt(defaultGasLimit)
    }

    private var defaultGasLimit: Int64 {
        coin.isNativeToken ? EVMHelper.defaultETHTransferGasUnit : EVMHelper.defaultERC20TransferGasUnit
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

    func validateToAddress() async -> Bool {
        guard !toAddress.isEmpty else { return false }
        do {
            let originalInput = toAddress
            let resolvedAddress = try await addressResolver(originalInput, coin.chain)
            if originalInput != resolvedAddress {
                toAddress = resolvedAddress
                toAddressLabel = originalInput
                lastResolvedAddress = resolvedAddress
            } else if originalInput != lastResolvedAddress {
                toAddressLabel = nil
                lastResolvedAddress = nil
            }
            isNamespaceResolved = true
            return true
        } catch {
            isNamespaceResolved = false
            return false
        }
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

    /// Convert a fiat-typed value to the equivalent coin amount. Empty input
    /// clears `amount` instead of leaving a stale value (Phase D lesson).
    func convertFiatToCoin(newValue: String) {
        guard let coinAmount = SendCryptoLogic.fiatToCoinAmount(fiat: newValue, coin: coin) else {
            amount = ""
            return
        }
        amount = coinAmount
        sendMaxAmount = false
        amountInFiat = newValue
    }

    /// Convert a coin-typed value to its fiat equivalent. `setMaxValue` mirrors
    /// the legacy flag — when true, this update is from the max-amount path
    /// and shouldn't reset the sendMaxAmount flag.
    func convertToFiat(newValue: String, setMaxValue: Bool = false) {
        guard let fiatAmount = SendCryptoLogic.coinAmountToFiat(amount: newValue, coin: coin) else {
            amountInFiat = ""
            sendMaxAmount = setMaxValue ? sendMaxAmount : false
            return
        }
        amountInFiat = fiatAmount
        sendMaxAmount = setMaxValue
        amount = newValue
    }

    // MARK: - Max amount

    /// Fill the amount from a percentage preset (25 / 50 / 75 / Max).
    ///
    /// The displayed amount fills **synchronously** from `coin.balanceDecimal`
    /// in every case so the field updates instantly like manual entry — no
    /// blocking `isLoading`, no awaited fetch on the hot path. Only the
    /// native-coin Max case needs a real fee (you can't drain the wallet and
    /// still pay gas), so it fills optimistically with the full balance and
    /// then refines to `balance − fee` in the background (Option B). Partials
    /// and non-native sends never reserve a fee — the Verify screen owns the
    /// precise fee validation before signing.
    func setMaxAmount(percentage: Double = 100) {
        cancelFeeRefine()
        errorMessage = ""

        sendMaxAmount = percentage == 100

        // Optimistic / instant fill: full balance minus zero fee, scaled by %.
        let fullBalance = SendCryptoLogic.computeMaxAmount(coin: coin, fee: .zero)
        amount = sendMaxAmount
            ? fullBalance
            : SendCryptoLogic.applyPercentage(maxAmount: fullBalance, percentage: percentage, coinDecimals: coin.decimals)
        convertToFiat(newValue: amount, setMaxValue: sendMaxAmount)

        // Only native-coin Max needs the fee subtracted; refine in the
        // background without blocking the field or the preset buttons.
        guard coin.isNativeToken, sendMaxAmount else { return }
        startFeeRefine()
    }

    /// Background refine for the native-coin Max path. Re-fetches the real
    /// max-send fee and settles `amount` to `balance − fee`. Guarded so a
    /// stale refine can't clobber a newer fill (another preset tap, manual
    /// edit) — the task is cancelled at the top of `setMaxAmount`, and we
    /// re-check cancellation after the await before writing.
    private func startFeeRefine() {
        isCalculatingFee = true
        feeRefineTask = Task { [weak self] in
            guard let self else { return }
            defer { self.isCalculatingFee = false }
            do {
                let result = try await self.interactor.fetchGasAndFee(SendFeeEstimateRequest(chainSpecific: SendChainSpecificRequest(
                    coin: self.coin,
                    toAddress: self.toAddress.isEmpty ? self.coin.address : self.toAddress,
                    amount: .zero,
                    memo: self.memo.isEmpty ? nil : self.memo,
                    sendMaxAmount: true,
                    isDeposit: self.isDeposit,
                    transactionType: self.transactionType,
                    gasLimit: self.gasLimit,
                    feeMode: self.feeMode,
                    fromAddress: self.fromAddress
                )))
                // Skip the refine write if the user moved off Max in the
                // meantime — a manual amount edit flips `sendMaxAmount` via
                // `convertToFiat` without cancelling this task, so guard on it
                // too or we'd clobber their input.
                guard !Task.isCancelled, self.sendMaxAmount else { return }
                let refined = SendCryptoLogic.computeMaxAmount(coin: self.coin, fee: result.fee)
                self.amount = refined
                self.convertToFiat(newValue: refined, setMaxValue: true)
            } catch is CancellationError {
                return
            } catch {
                // Keep the optimistic full-balance value rather than wiping the
                // field; the Verify screen recomputes and validates the real
                // fee before signing.
                guard !Task.isCancelled else { return }
                self.logger.error("setMaxAmount fee refine failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Cancel any in-flight native-Max fee refine and clear the indicator.
    private func cancelFeeRefine() {
        feeRefineTask?.cancel()
        feeRefineTask = nil
        isCalculatingFee = false
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
            let result = try await interactor.fetchGasAndFee(SendFeeEstimateRequest(chainSpecific: SendChainSpecificRequest(
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
            )))
            gas = result.gas
            fee = result.fee
        } catch {
            logger.error("loadGasInfo failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Error-state setters (single-call replacements for the trio of
    // `errorTitle = "error"; errorMessage = X; show*Alert = true` lines).

    private func setGeneralError(title: String = "error", message: String) {
        errorTitle = title
        errorMessage = message
        showAlert = true
    }

    private func setAddressError(title: String = "error", message: String) {
        errorTitle = title
        errorMessage = message
        showAddressAlert = true
    }

    private func setAmountError(title: String = "error", message: String) {
        errorTitle = title
        errorMessage = message
        showAmountAlert = true
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
            setGeneralError(message: "decimalAmountError".localized)
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

    // MARK: - Per-rule validators (composable, individually testable)

    /// Cosmos-style chains that surface pending transactions block until the
    /// previous one confirms. Other chains short-circuit through.
    func validatePendingTransaction() -> Bool {
        guard hasPendingTransaction && coin.chain.supportsPendingTransactions else {
            return true
        }
        setGeneralError(message: "pendingTransactionError")
        return false
    }

    /// Rejects empty/zero amounts before any balance math runs.
    func validateAmountNonZero() -> Bool {
        guard !amount.isEmpty, !amountDecimal.isZero else {
            setAmountError(message: "positiveAmountError")
            return false
        }
        return true
    }

    /// Rejects malformed addresses for the current coin's chain.
    func validateAddressFormat() -> Bool {
        guard isValidAddressFormat() else {
            setAddressError(message: "invalidAddressError")
            return false
        }
        return true
    }

    func validateAddressResolved() async -> Bool {
        guard await validateToAddress() else {
            setAddressError(message: "invalidAddressError")
            return false
        }
        return true
    }

    /// Rejects amount + fee > balance for the source coin. TRON staking is
    /// short-circuited because the validation already ran in
    /// `Tron{Freeze,Unfreeze}View` and the on-screen balance reflects it.
    /// For ERC20 sources, defers to `validateERC20GasBalance` for the gas
    /// half of the check.
    func validateBalance() -> Bool {
        let isTronStaking = coin.chain == .tron && isStakingOperation
        guard !isTronStaking else { return true }

        let exceeded = SendCryptoLogic.isAmountExceeded(
            coin: coin,
            amount: amount,
            sendMaxAmount: sendMaxAmount,
            fee: fee,
            gas: gas,
            isStakingOperation: isStakingOperation
        )
        if exceeded {
            setAmountError(message: "walletBalanceExceededError")
            return false
        }
        return validateERC20GasBalance()
    }

    /// For ERC20-style non-native sends, gas is paid in the chain's native
    /// sibling. Reject if the vault doesn't hold enough of it.
    func validateERC20GasBalance() -> Bool {
        guard !coin.isNativeToken,
              let nativeToken = vault.coins.nativeCoin(chain: coin.chain) else {
            return true
        }
        let nativeBalance = nativeToken.rawBalance.toBigInt(decimals: nativeToken.decimals)
        guard fee > nativeBalance else { return true }

        setGeneralError(message: String(format: "insufficientGasTokenError".localized, nativeToken.ticker, coin.ticker))
        return false
    }

    // Composed form-validation pipeline — every rule runs in order, stopping
    // at the first failure.
    func validateForm() async -> Bool {
        resetStates()
        isValidatingForm = true
        defer {
            isValidatingForm = false
            isLoading = false
        }

        guard validatePendingTransaction() else { return false }
        guard validateAmountNonZero() else { return false }
        guard await validateAddressResolved() else { return false }
        return validateBalance()
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
        lastResolvedAddress = nil
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
