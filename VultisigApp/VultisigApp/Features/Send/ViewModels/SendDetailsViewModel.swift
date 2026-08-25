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
    @ObservationIgnored private let logger = Log.send.viewModel
    @ObservationIgnored private let interactor: SendInteractor
    @ObservationIgnored private let addressResolver: (String, Chain) async throws -> String

    /// Chain-agnostic async amount validators (see `SendAmountValidator`). The
    /// first applicable one to object wins; XRP ships the only implementation
    /// today. Injected so tests can script the underlying service.
    @ObservationIgnored private let amountValidators: [any SendAmountValidator]

    // MARK: - Identity (immutable once set)
    let vault: Vault
    let hasPreselectedCoin: Bool

    /// XRP-only Destination Tag concern (field state, X-address autofill/lock
    /// lifecycle, RequireDest gate). Read/bound through the parent so `@Observable`
    /// tracks its nested state.
    let rippleTag: RippleDestinationTagViewModel

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

    /// Records the user's "Continue anyway" on the unverified-RequireDest
    /// confirm for the current destination. Forwards the parent-owned
    /// `toAddress` to the tag sub-VM that owns the acknowledgment.
    func acknowledgeUnverifiedDestinationTag() {
        rippleTag.acknowledge(toAddress: toAddress)
    }
    var feeMode: FeeMode = .default
    var sendMaxAmount: Bool = false
    var isStakingOperation: Bool = false
    var transactionType: VSTransactionType = .unspecified
    var memoFunctionDictionary: [String: String] = [:]
    var wasmContractPayload: WasmExecuteContractPayload? = nil

    // MARK: - Fee / gas (derived from interactor calls)
    var gas: BigInt = .zero
    var fee: BigInt = .zero

    /// A gas limit together with the asset it was sized for.
    ///
    /// Reads are asset-scoped, so a limit self-invalidates the moment the form
    /// moves to another coin or chain and no view has to remember to clear it.
    /// The key is `Coin.uniqueId` (chain + ticker + contract): it ignores the
    /// address, which is right here because the vault is fixed for the life of
    /// the form, and it is stable across `Coin` instances for the same asset.
    private struct AssetScopedGasLimit {
        private var limit: BigInt?
        private var assetId: String?

        func value(for coin: Coin) -> BigInt? {
            guard let assetId, assetId == coin.uniqueId else { return nil }
            return limit
        }

        mutating func set(_ newValue: BigInt?, for coin: Coin) {
            limit = newValue
            assetId = newValue == nil ? nil : coin.uniqueId
        }
    }

    private var stampedEstimatedGasLimit = AssetScopedGasLimit()
    private var stampedCustomGasLimit = AssetScopedGasLimit()

    /// The limit the current fee was estimated against — the real
    /// `eth_estimateGas` result, adopted whenever the user hasn't pinned one.
    ///
    /// Asset-scoped for the same reason as `customGasLimit`, and it has to be:
    /// `gasLimit` falls back to it, `BlockChainService` treats the requested
    /// limit as a *floor* rather than a suggestion, and the gas sheet is seeded
    /// with `gasLimit` and re-pins whatever it displays on Save. A stale
    /// estimate from another asset would therefore both inflate the reserved
    /// amount and offer the user a foreign number to confirm — which is how a
    /// pin scoped to one asset would come back on the next.
    var estimatedGasLimit: BigInt? {
        get { stampedEstimatedGasLimit.value(for: coin) }
        set { stampedEstimatedGasLimit.set(newValue, for: coin) }
    }

    /// The user-pinned gas limit from the gas settings sheet.
    ///
    /// A gas limit prices the execution of one specific call, not a chain: a
    /// native transfer is sized at 23,000 units where an ERC20 transfer is
    /// sized at 120,000 (`defaultGasLimit` below already branches on exactly
    /// that), and a token with transfer hooks costs more again. So the stamp is
    /// the *asset*, not the chain — a limit pinned for ETH must not size a USDC
    /// send on the same chain. Too low is the dangerous direction: the
    /// transaction runs out of gas on-chain, which burns the fee and delivers
    /// nothing.
    ///
    /// The coin picker writes `coin` directly and no view owns clearing this,
    /// so the binding is enforced here rather than left to a caller to
    /// remember: the limit is only visible while the form is still on the asset
    /// it was sized for, and re-pinning re-stamps.
    var customGasLimit: BigInt? {
        get { stampedCustomGasLimit.value(for: coin) }
        set { stampedCustomGasLimit.set(newValue, for: coin) }
    }

    /// Backing storage for `customByteFee`, plus the chain it was pinned for.
    private var pinnedByteFee: BigInt? = nil
    private var pinnedByteFeeChain: Chain? = nil

    /// The user-pinned sat/vB rate from the gas settings sheet.
    ///
    /// A byte rate is meaningless off its own chain — DOGE quotes six figures
    /// per byte where BTC quotes tens — so one pinned for BTC must never price a
    /// later LTC or DOGE send. The coin picker writes `coin` directly and no
    /// view owns clearing this, so the binding is enforced here rather than left
    /// to a caller to remember: the rate is only visible while the form is still
    /// on the chain it was set for, and re-pinning re-stamps the chain.
    ///
    /// The chain is the whole identity for a rate: it is a property of that
    /// chain's fee market and holds for every asset on it. `customGasLimit`
    /// is deliberately stricter — it prices one specific call, so it is
    /// stamped with the asset.
    var customByteFee: BigInt? {
        get {
            guard let pinnedByteFeeChain, pinnedByteFeeChain == coin.chain else { return nil }
            return pinnedByteFee
        }
        set {
            pinnedByteFee = newValue
            pinnedByteFeeChain = newValue == nil ? nil : coin.chain
        }
    }

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

    /// Result of the async, chain-agnostic amount validators (see
    /// `SendAmountValidator`): the inline message to render under the amount
    /// field and whether it blocks Continue. Kept separate from the sync
    /// alert-style `errorMessage` so the async, self-clearing check can't race
    /// the synchronous validators. The message is already localized + formatted
    /// (render directly, not through `NSLocalizedString`). For XRP this
    /// complements — never replaces — the Verify-screen guard, the fail-closed
    /// backstop.
    var amountValidation: SendAmountValidationState = .valid

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
    /// Monotonic token bumped on every new/cancelled resolution request. The
    /// resolver may not honor `Task` cancellation, so the async body compares
    /// this before publishing — a stale verdict must never overwrite the
    /// pending (`nil`) state and flash an error on the current input.
    @ObservationIgnored private var addressResolutionGeneration = 0
    @ObservationIgnored private var amountValidationTask: Task<Void, Never>?

    /// Background fee refine for the native-coin Max path. Exposed so the UI
    /// (and tests) can observe / await the optimistic-fill → refine settle.
    @ObservationIgnored private(set) var feeRefineTask: Task<Void, Never>?

    // MARK: - Init

    init(
        coin: Coin,
        vault: Vault,
        hasPreselectedCoin: Bool = false,
        interactor: SendInteractor = DefaultSendInteractor.live,
        addressResolver: @escaping (String, Chain) async throws -> String = AddressService.resolveInput,
        amountValidators: [any SendAmountValidator] = [RippleDestinationReserveValidator()],
        destinationTagRequirementProvider: ((String) async -> RippleDestinationTagRequirement)? = nil
    ) {
        self.coin = coin
        self.vault = vault
        self.hasPreselectedCoin = hasPreselectedCoin
        self.fromAddress = coin.address
        self.interactor = interactor
        self.addressResolver = addressResolver
        self.amountValidators = amountValidators
        self.rippleTag = RippleDestinationTagViewModel(requirementProvider: destinationTagRequirementProvider)
    }

    func hydrate(from seed: SendDetailsSeed) {
        // The seed replaces every field, including the max intent, so nothing
        // derived from the state it replaces may still land: drop the pending
        // keystroke commit and the background max-fee refine alike.
        cancelPendingAmountCommit()
        cancelFeeRefine()
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

    /// Continue button is disabled while either async path is running, or while
    /// an amount validator is presenting a blocking message (e.g. an XRP send
    /// below the destination's base reserve).
    var continueButtonDisabled: Bool {
        isLoading || isValidatingForm || amountValidation.blocksContinue
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
        addressResolutionGeneration &+= 1
        isAddressResolved = nil
        // Resolution is pending — keep the inline error cleared so it doesn't
        // flash while the user is still typing; a definitive failure re-shows it.
        showAddressAlert = false
        let generation = addressResolutionGeneration
        addressResolutionTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, !Task.isCancelled else { return }
            // Resolve through the generation-guarded path: a late/uncancelled
            // resolver must neither publish a stale verdict nor rewrite
            // `toAddress` over a newer recipient the user has since typed.
            guard let resolved = await self.resolveToAddressIfCurrent(generation: generation) else { return }
            self.isAddressResolved = resolved
        }
    }

    func cancelAddressResolution() {
        addressResolutionTask?.cancel()
        addressResolutionGeneration &+= 1
        isAddressResolved = nil
        // Dropping the in-flight verdict returns to the pending state — clear
        // any stale inline error so editing the recipient never leaves a
        // no-longer-true message on screen.
        showAddressAlert = false
    }

    /// XRP address seam: when the destination input is a mainnet X-address,
    /// replace it with the embedded classic r-address (keeping the original
    /// X string visible as the label, ENS-style) and autofill + lock the
    /// Destination Tag if one is embedded. Runs on both the sync
    /// format-validation path and the async resolution path, so paste, QR
    /// scan, address book, and deeplinks are all covered. The classic
    /// address is what reaches `SendTransaction`/`KeysignPayload` — verify,
    /// the security scanner, and tx history all agree with what is signed,
    /// and the signer's X-address/tag conflict error becomes unreachable.
    private func normalizeRippleXAddressIfNeeded() {
        guard coin.chain == .ripple else { return }
        guard let decoded = try? RippleXAddress.decode(toAddress) else {
            // The input is no longer the X-address that locked the tag —
            // the derived tag belonged to the old destination, drop it.
            rippleTag.handleAddressChangedAway(isStillResolved: toAddress == lastResolvedAddress)
            return
        }

        // Address fields are the parent's (shared with the ENS/name path); the
        // tag/lock decision belongs to the XRP-only sub-VM.
        let original = toAddress
        toAddress = decoded.classicAddress
        toAddressLabel = original
        lastResolvedAddress = decoded.classicAddress

        rippleTag.applyDecodedTag(decoded.tag)
    }

    /// Called when the destination field is cleared. Drops the resolution
    /// bookkeeping and any X-address-derived tag so a stale locked tag
    /// can't ride onto the next address the user enters — the empty-field
    /// path never reaches `normalizeRippleXAddressIfNeeded()`, which is
    /// where edits-away normally release the lock.
    func onToAddressCleared() {
        addressSetupDone = false
        toAddressLabel = nil
        lastResolvedAddress = nil
        // An empty field is not an "invalid recipient" — drop any inline error
        // so it doesn't hang under a blank input.
        showAddressAlert = false
        rippleTag.releaseLockedTag()
    }

    /// Surfaces the chain-general "invalid recipient" inline error under the
    /// destination field, so a definitive resolution failure disables Continue
    /// *with a visible reason* rather than silently. No-op for an empty field:
    /// the empty state is owned by `onToAddressCleared`, and an error under a
    /// blank input would just be noise. The error clears on correction — a
    /// valid format (`isValidAddressFormat`), a cleared field
    /// (`onToAddressCleared`), or a fresh resolution attempt
    /// (`cancelAddressResolution` / `debouncedResolveAddress`) all reset it.
    func markInvalidRecipient() {
        guard !toAddress.isEmpty else { return }
        setAddressError(message: "invalidRecipientAddressError")
    }

    /// Paste / QR / address-book commit that did not switch chains: surface the
    /// inline error only for a value that can never resolve to a valid
    /// recipient. A value that is valid for the current chain, or a name-service
    /// candidate (ENS/`.sol`, or a THORChain-family TNS name) that async
    /// resolution might still resolve, is deliberately left alone so those never
    /// flash an error before the async path (`isAddressResolved`) reaches a
    /// definitive verdict.
    func markInvalidRecipientIfUnresolvable() {
        guard !toAddress.isEmpty else { return }
        guard !AddressService.validateRecipientAddress(address: toAddress, chain: coin.chain) else { return }
        guard !toAddress.isENSNameService() else { return }
        let resolvesNames: Set<Chain> = [.thorChain, .thorChainChainnet, .thorChainStagenet]
        guard !resolvesNames.contains(coin.chain) else { return }
        markInvalidRecipient()
    }

    func validateToAddress() async -> Bool {
        guard !toAddress.isEmpty else { return false }
        normalizeRippleXAddressIfNeeded()
        let originalInput = toAddress
        do {
            let resolvedAddress = try await addressResolver(originalInput, coin.chain)
            commitResolvedAddress(originalInput: originalInput, resolvedAddress: resolvedAddress)
            return true
        } catch {
            isNamespaceResolved = false
            return false
        }
    }

    /// Generation-guarded resolution for the debounced background task. Resolves
    /// the current input but commits *nothing* — neither the address rewrite nor
    /// the verdict — when a newer request has bumped `addressResolutionGeneration`
    /// during the (possibly network-bound) await. Because `addressResolver` may
    /// not honor `Task` cancellation, this guard is what prevents a late verdict
    /// from clobbering a recipient the user has since re-typed. Returns `nil`
    /// when the request was superseded.
    private func resolveToAddressIfCurrent(generation: Int) async -> Bool? {
        guard !toAddress.isEmpty else { return false }
        normalizeRippleXAddressIfNeeded()
        let originalInput = toAddress
        do {
            let resolvedAddress = try await addressResolver(originalInput, coin.chain)
            guard addressResolutionGeneration == generation else { return nil }
            commitResolvedAddress(originalInput: originalInput, resolvedAddress: resolvedAddress)
            return true
        } catch {
            guard addressResolutionGeneration == generation else { return nil }
            isNamespaceResolved = false
            return false
        }
    }

    /// Applies a successful resolution to the address fields. Shared by the
    /// synchronous-await path (`validateToAddress`) and the generation-guarded
    /// background path so both commit identically.
    private func commitResolvedAddress(originalInput: String, resolvedAddress: String) {
        if originalInput != resolvedAddress {
            toAddress = resolvedAddress
            toAddressLabel = originalInput
            lastResolvedAddress = resolvedAddress
        } else if originalInput != lastResolvedAddress {
            toAddressLabel = nil
            lastResolvedAddress = nil
        }
        isNamespaceResolved = true
    }

    func isValidAddressFormat() -> Bool {
        guard !toAddress.isEmpty else { return false }
        normalizeRippleXAddressIfNeeded()
        let isValid = AddressService.validateRecipientAddress(address: toAddress, chain: coin.chain)
        if isValid {
            showAddressAlert = false
            errorMessage = nil
        }
        return isValid
    }

    // MARK: - Amount editing

    /// How long the amount fields wait after the last keystroke before the typed
    /// value is committed (converted into the other field, max intent settled).
    private static let amountCommitDebounce: Duration = .milliseconds(500)

    /// The commit armed by the last keystroke in either amount field, while it
    /// is still pending.
    ///
    /// A superseded commit has to be **cancelled**, not merely detected and
    /// skipped. Detection would have to compare the commit's value against the
    /// field, and that cannot tell the two intents apart: typing the full
    /// balance and then tapping Max produces the *same string*. Applying the
    /// typed one clears `sendMaxAmount` while the amount stays at the full
    /// balance — the state that makes WalletCore's exact coin selector try to
    /// fund `balance + fee` out of `balance`, return no inputs, and surface as a
    /// generic "insufficient UTXOs available" on a healthy wallet.
    ///
    /// Cancelling is only meaningful if the debouncer is *owned*: a process-wide
    /// one holds a single slot any caller can steal, so it can express "whatever
    /// was last debounced anywhere", never "this form's pending amount commit".
    /// One slot per form gives both halves of the ordering — the two fields
    /// share it, so moving from the crypto field to the fiat field cancels the
    /// field the user left, and every path that writes the amount itself cancels
    /// it before writing (see `cancelPendingAmountCommit`).
    ///
    /// Exposed (like `feeRefineTask`) so tests can await the settle.
    @ObservationIgnored private(set) var amountCommitTask: Task<Void, Never>?

    /// Arm the debounced commit for a keystroke, replacing any commit still
    /// pending. `delayedTask` sleeps before running `commit`, so cancelling the
    /// task stops the commit at that checkpoint and swallows the cancellation —
    /// a superseded keystroke is ordinary control flow, not a failure.
    ///
    /// The slot holds only *pending* commits: a commit that has passed the
    /// checkpoint releases it before running, so its own conversion doesn't find
    /// the task that is executing it and cancel that.
    private func scheduleAmountCommit(_ commit: @MainActor @escaping () -> Void) {
        amountCommitTask?.cancel()
        amountCommitTask = delayedTask(after: Self.amountCommitDebounce) { [weak self] in
            self?.amountCommitTask = nil
            commit()
        }
    }

    /// Called by every path that writes the amount fields itself — a
    /// percentage/Max preset, a QR/deeplink fill, a coin switch, the background
    /// max-fee refine's commit, a reset, a re-hydrate. The pending keystroke
    /// commit is dropped, so it cannot land afterwards and undo the write.
    ///
    /// This is the half a shared debouncer could not provide: none of those paths
    /// arm a debounce, so they had nothing of their own to cancel and the stale
    /// commit ran regardless.
    ///
    /// Those paths cancel *within the same main-actor turn* as their write, and
    /// nothing suspends in between, so a pending commit cannot interleave —
    /// whether the cancel comes before the write (`setMaxAmount`) or with the
    /// conversion that follows it (the QR fill, the fee refine).
    private func cancelPendingAmountCommit() {
        amountCommitTask?.cancel()
        amountCommitTask = nil
    }

    /// A keystroke in the crypto amount field, reported by the field's binding
    /// after it has written `amount`. The conversion is debounced; the max-send
    /// intent is dropped now (see `dropMaxIntentForUserEdit`).
    func onAmountFieldEdited(_ newValue: String) {
        dropMaxIntentForUserEdit()
        scheduleAmountCommit { [weak self] in self?.convertToFiat(newValue: newValue) }
    }

    /// A keystroke in the fiat amount field. Shares the crypto field's single
    /// pending slot, so an in-flight commit from the field the user just left
    /// cannot clobber the one they moved to.
    func onFiatAmountFieldEdited(_ newValue: String) {
        dropMaxIntentForUserEdit()
        scheduleAmountCommit { [weak self] in self?.convertFiatToCoin(newValue: newValue) }
    }

    /// The part of a keystroke that must not wait for the debounce.
    ///
    /// Continue does not wait for a pending commit, so if the max-send intent
    /// only lapsed when the commit ran, `makeTransaction` could snapshot a
    /// hand-typed amount still flagged `sendMaxAmount` — and a UTXO signer would
    /// sweep the wallet for a user who asked to send a specific figure. Both
    /// entry points run this on the main actor before any suspension point, so
    /// no Continue tap can observe the intent the keystroke has already dropped.
    ///
    /// The inverse property is the cancellation above, and the two are
    /// independent: a *superseded* commit is cancelled and so cannot clear the
    /// flag, while a *genuine* edit clears it immediately.
    private func dropMaxIntentForUserEdit() {
        sendMaxAmount = false
    }

    // MARK: - Fiat / crypto conversion

    /// Convert a fiat-typed value to the equivalent coin amount. Empty input
    /// clears `amount` instead of leaving a stale value (Phase D lesson).
    ///
    /// Typing a fiat figure is an explicit amount choice, so it drops the
    /// max-send flag — including on the clearing branch, where leaving the flag
    /// set would pair "send everything" with an empty amount field.
    func convertFiatToCoin(newValue: String) {
        cancelPendingAmountCommit()
        guard let coinAmount = SendCryptoLogic.fiatToCoinAmount(fiat: newValue, coin: coin) else {
            amount = ""
            sendMaxAmount = false
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
        cancelPendingAmountCommit()
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
        // Drop any amount-field commit still pending: the preset is the newer
        // intent, and a late commit must not undo it.
        cancelPendingAmountCommit()
        errorMessage = ""
        // Drop a planner verdict left over from a previous preset — this attempt
        // gets to state its own outcome.
        showAmountAlert = false

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

    /// Background refine for the native-coin Max path. Settles the optimistic
    /// full-balance fill to what can really be sent.
    ///
    /// Its ordering against the amount fields rests on three guards, which
    /// between them cover every writer of the amount:
    ///
    /// - paths that replace the amount while *keeping* the max intent cancel
    ///   this task first (`setMaxAmount`, `hydrate`), so `Task.isCancelled`
    ///   catches them;
    /// - every path that replaces it with an *explicit* amount clears
    ///   `sendMaxAmount` as it does so — a keystroke included, which drops the
    ///   intent synchronously in `onAmountFieldEdited` rather than waiting for
    ///   its debounced commit;
    /// - the coin picker replaces the *asset* under an unchanged max intent
    ///   without cancelling anything, so the asset the user tapped Max on is
    ///   compared against the one the form is on (`isStillOn(_:)`) — twice:
    ///   before the request is built, and again before its result is written.
    ///
    /// The first two are re-checked after the await; the asset is checked on
    /// both sides of it. So a refine settling into any kind of newer state
    /// stands down instead of clobbering it.
    ///
    /// The asset is read *here*, not in the task body. An unstructured `Task`
    /// inherits the actor but is scheduled rather than run inline, so the main
    /// actor gets a turn — enough for the picker to write `coin` — between this
    /// line and the body's first. Reading it inside would let the task adopt
    /// the new asset as its own request and refine *that* under a max intent
    /// the user formed on the old one, which is the same "send everything"
    /// the user never asked for, arrived at by a scheduling coin flip.
    private func startFeeRefine() {
        let requestedAsset = coin.uniqueId
        isCalculatingFee = true
        feeRefineTask = Task { [weak self] in
            guard let self else { return }
            // Installed before the asset check so standing down still takes the
            // calculating indicator down with it — nothing else would.
            defer { self.isCalculatingFee = false }
            guard self.isStillOn(requestedAsset) else { return }
            do {
                if self.coin.chainType == .UTXO {
                    try await self.refineMaxFromPlan(asset: requestedAsset)
                } else {
                    try await self.refineMaxFromFee(asset: requestedAsset)
                }
            } catch is CancellationError {
                return
            } catch {
                // Same guards as the success paths: a verdict about a max send
                // the user has already moved off — in amount or in asset — must
                // not paint an alert on what they are looking at instead.
                guard !Task.isCancelled, self.sendMaxAmount, self.isStillOn(requestedAsset) else { return }
                self.handleMaxRefineFailure(error)
            }
        }
    }

    /// Whether the form is still on the asset an in-flight request asked about.
    ///
    /// A fee result describes the asset it was requested for, and the coin
    /// picker can replace that asset mid-flight: it cancels nothing and it
    /// leaves the max intent alone, so neither of the other two guards catches
    /// it. Without this, a result for the old asset would be written — and,
    /// worse, *stamped* — against the new one, which is exactly the leak the
    /// asset stamp exists to close.
    private func isStillOn(_ requestedAsset: String) -> Bool {
        coin.uniqueId == requestedAsset
    }

    /// The max-send request for the current form state. `amount` differs by
    /// path: the UTXO planner is handed the whole balance (it ignores the value
    /// in max mode and derives the output from the selected inputs), while the
    /// flat-fee estimate keeps passing zero so an EVM `eth_estimateGas` isn't
    /// simulated against a value the account can't also cover gas for.
    private func maxSendRequest(amount: BigInt) -> SendChainSpecificRequest {
        SendChainSpecificRequest(
            coin: coin,
            // The output script type affects the transaction's size, hence the
            // fee, so planning needs an address — fall back to our own.
            toAddress: toAddress.isEmpty ? coin.address : toAddress,
            amount: amount,
            memo: memo.isEmpty ? nil : memo,
            sendMaxAmount: true,
            isDeposit: isDeposit,
            transactionType: transactionType,
            gasLimit: gasLimit,
            customGasLimit: customGasLimit,
            customByteFee: customByteFee,
            feeMode: feeMode,
            fromAddress: fromAddress
        )
    }

    /// UTXO Max. A sat/vB rate is not a fee: the fee is `rate × size`, and the
    /// size only exists once inputs are selected. Ask WalletCore what a real
    /// `useMaxAmount` transaction would send and cost, and show exactly that —
    /// so the Details figure is the one Verify will confirm rather than
    /// `balance − rate`, which reserves roughly a dozen sats for a fee of a few
    /// thousand.
    private func refineMaxFromPlan(asset requestedAsset: String) async throws {
        // The planner ignores this value in max mode, but it still reaches
        // WalletCore's `Int64` amount field, where an out-of-range conversion
        // traps rather than failing. Clamp it — an absurd balance must not
        // crash the form.
        let probeAmount = Swift.min(coin.balanceRaw, BigInt(Int64.max))
        // The form plans against the cached UTXO set: Max is tapped repeatedly
        // while editing, and Verify refreshes before the plan that is signed.
        let plan = try await interactor.calculateMaxSendPlan(
            maxSendRequest(amount: probeAmount),
            vault: vault,
            refreshUtxos: false
        )
        guard !Task.isCancelled, sendMaxAmount, isStillOn(requestedAsset) else { return }
        // `gas` stays the rate (what the gas sheet edits); `fee` becomes the
        // planned total, so the balance guard compares against a real number
        // and the hand-off transaction carries an honest fee into Verify.
        gas = plan.byteFee
        fee = plan.fee
        let refined = SendCryptoLogic.formatRawAmount(plan.amount, coin: coin)
        amount = refined
        convertToFiat(newValue: refined, setMaxValue: true)
    }

    /// Every other native chain: the chain quotes a flat fee, so `balance − fee`
    /// is the max.
    private func refineMaxFromFee(asset requestedAsset: String) async throws {
        let result = try await interactor.fetchGasAndFee(SendFeeEstimateRequest(chainSpecific: maxSendRequest(amount: .zero)))
        guard !Task.isCancelled, sendMaxAmount, isStillOn(requestedAsset) else { return }
        if customGasLimit == nil, let resolvedGasLimit = result.gasLimit {
            estimatedGasLimit = resolvedGasLimit
        }
        let refined = SendCryptoLogic.computeMaxAmount(coin: coin, fee: result.fee)
        amount = refined
        convertToFiat(newValue: refined, setMaxValue: true)
    }

    /// Keep the optimistic full-balance fill on a transport failure — the Verify
    /// screen recomputes and validates the real fee before signing, so a flaky
    /// lookup must not wipe the field or block the flow.
    ///
    /// A planner or UTXO-selection verdict is different in kind: it will not
    /// resolve itself on retry, and leaving it silent until Verify is exactly
    /// the late, mislabelled failure this path exists to prevent. Surface it
    /// inline, under the amount field, while the amount is still editable.
    private func handleMaxRefineFailure(_ error: Error) {
        logger.error("setMaxAmount fee refine failed: \(error.localizedDescription, privacy: .public)")
        switch error {
        case is UTXOTransactionPlanError, is KeysignPayloadFactory.Errors:
            setAmountError(message: error.localizedDescription)
        default:
            break
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
        let requestedAsset = coin.uniqueId

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
                customGasLimit: customGasLimit,
                customByteFee: customByteFee,
                feeMode: feeMode,
                fromAddress: fromAddress
            )))
            // The picker can swap the asset while this is in flight; figures
            // for the one the form has left must not land on the one it is on.
            guard isStillOn(requestedAsset) else { return }
            gas = result.gas
            fee = result.fee
            // Adopt the real estimate so the displayed fee, and the gas limit
            // seeded into the gas-settings sheet, reflect it. A user override
            // (customGasLimit) still wins via the `gasLimit` computed property.
            if customGasLimit == nil, let resolvedGasLimit = result.gasLimit {
                estimatedGasLimit = resolvedGasLimit
            }
        } catch {
            logger.error("loadGasInfo failed: \(error.localizedDescription, privacy: .public)")
            guard isStillOn(requestedAsset) else { return }
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

    // MARK: - Async amount validation (chain-agnostic; see SendAmountValidator)

    /// Value-type snapshot of the inputs the amount validators read. Built on
    /// the main actor so no `@Model` `Coin` crosses into async validator work.
    private var currentAmountValidationInput: SendAmountValidationInput {
        SendAmountValidationInput(
            chain: coin.chain,
            isNativeToken: coin.isNativeToken,
            toAddress: toAddress,
            amount: amount,
            amountDecimal: amountDecimal,
            amountRaw: amountInRaw
        )
    }

    /// Debounced inline amount validation. Cancels any in-flight run; clears the
    /// message synchronously when no validator applies (so removing the address
    /// clears the warning immediately, not after the debounce); otherwise
    /// schedules the check after a short debounce. Validators cache their
    /// per-destination verdict, so amount edits don't re-hit the node.
    func debouncedValidateAmount() {
        amountValidationTask?.cancel()
        let input = currentAmountValidationInput
        guard amountValidators.contains(where: { $0.isApplicable(to: input) }) else {
            amountValidation = .valid
            return
        }
        amountValidationTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.5))
            guard let self, !Task.isCancelled else { return }
            await self.refreshAmountValidation()
        }
    }

    /// While-typing entry point: runs the applicable validators with the cached
    /// verdict and publishes the result (clearing it when none applies).
    func refreshAmountValidation() async {
        _ = await runAmountValidation(forceRefresh: false)
    }

    /// Continue-time gate: runs the applicable validators live (`forceRefresh`)
    /// so the block decision can never diverge from the fail-closed backstop
    /// (e.g. an XRP destination funded mid-session must not stay blocked on a
    /// cached verdict), publishes the result, and returns `false` when any
    /// validator blocks Continue.
    func validateAmountConstraints() async -> Bool {
        !(await runAmountValidation(forceRefresh: true).blocksContinue)
    }

    /// Snapshot the inputs, run the applicable validators (first to object
    /// wins), and — only if the form hasn't moved on since the snapshot —
    /// publish the result. Fails open: a validator that returns `.ok` (or none
    /// applying) yields `.valid`. Returns the resolved state for the
    /// Continue-path decision, computed from the same snapshot, so a late edit
    /// that skips the publish still returns the right verdict.
    @discardableResult
    private func runAmountValidation(forceRefresh: Bool) async -> SendAmountValidationState {
        let input = currentAmountValidationInput
        var state = SendAmountValidationState.valid
        for validator in amountValidators where validator.isApplicable(to: input) {
            if case let .invalid(message, blocksContinue) = await validator.validate(input, forceRefresh: forceRefresh) {
                state = SendAmountValidationState(message: message, blocksContinue: blocksContinue)
                break
            }
        }

        // Publish only if the form hasn't moved on (a newer amount/address, a
        // chain switch, or a reset/cancel while the lookup was in flight) so a
        // late result can't write a stale message.
        if !Task.isCancelled, currentAmountValidationInput == input {
            amountValidation = state
        }
        return state
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
            setAddressError(message: "invalidRecipientAddressError")
            return false
        }
        return true
    }

    func validateAddressResolved() async -> Bool {
        guard await validateToAddress() else {
            setAddressError(message: "invalidRecipientAddressError")
            return false
        }
        return true
    }

    /// TRON self-send guard (parity with android DefaultSendStrategy): a plain
    /// transfer whose destination is the sender's own address just burns fees.
    /// Staking ops (freeze/unfreeze) are self-directed by design, so they're
    /// excluded via the existing `isStakingOperation` flag. Compares against
    /// `fromAddress` — the sender `makeTransaction()` actually signs with, which
    /// a hydrated seed can decouple from `coin.address` — so the guard tracks the
    /// real sender rather than an assumed-equal default.
    func validateNotSelfSend() -> Bool {
        guard coin.chain == .tron, !isStakingOperation else { return true }
        guard toAddress == fromAddress else { return true }
        setAddressError(message: "sameAddressError")
        return false
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

        // Existential-deposit guard for ED-bearing chains (DOT) that reap
        // the *sender*. Block here — before the keysign ceremony — rather than
        // letting `transfer_keep_alive` fail on-chain with the fee already
        // charged. Skipped for non-native tokens (ED applies to the native
        // account, not token transfers). Inert for XRP: its rawBalance is
        // already reserve-net, so the amount-exceeded check is the reserve
        // guard and a remainder below 1 XRP spendable is valid on-chain.
        if coin.isNativeToken {
            if SendCryptoLogic.canBeReaped(coin: coin, amount: amount, gas: fee) {
                setAmountError(message: "belowExistentialDepositError".localized)
                return false
            }
        }

        // Some chains enforce a protocol minimum value on every output; a
        // native send below it is silently dropped by the node. Match Android
        // by blocking it here before the keysign ceremony.
        if SendCryptoLogic.isBelowMinimumSendAmount(coin: coin, amount: amount),
           let minimum = coin.chain.minimumSendAmount {
            let minAmount = coin.decimal(for: minimum).description
            setAmountError(message: String(format: "cardanoMinimumSendAmountError".localized, minAmount))
            return false
        }

        return validateERC20GasBalance()
    }

    /// XRP tag/memo contract, resolved at the form seam so the failure is
    /// actionable while the fields are still on screen:
    /// - the Destination Tag field must be empty or a canonical uint32 decimal;
    /// - a TEXT memo is accepted again (restored on-chain memo support) — on its
    ///   own, or riding alongside a tag as the tag+memo combo;
    /// - a numeric memo alongside a DIFFERENT tag is a conflict (the wire would
    ///   read two tags).
    func validateRippleTagAndMemo() -> Bool {
        guard coin.chain == .ripple else { return true }

        guard let errorKey = rippleTag.validateTagAndMemo(memo: memo).errorKey else {
            return true
        }
        setGeneralError(message: errorKey)
        return false
    }

    /// Effective XRP destination tag: the dedicated field wins; a canonical
    /// numeric memo (legacy workaround) is honored when the field is empty.
    /// Only meaningful after `validateRippleTagAndMemo()` passed.
    var resolvedDestinationTag: UInt32? {
        guard coin.chain == .ripple else { return nil }
        return rippleTag.resolvedTag(memo: memo)
    }

    /// RequireDest gate: a tagless XRP send to a destination whose
    /// AccountRoot sets `lsfRequireDestTag` would be rejected by the ledger
    /// (or worse, credited to nobody if the flag is off but the tag was
    /// still needed by the exchange) — hard-block it here where the tag
    /// field is still on screen. Lookup failure fails OPEN behind an
    /// explicit per-address acknowledgment: XRPL public-RPC availability
    /// must not become a hard dependency for every XRP send (the fee lookup
    /// deliberately fails open on the same RPC), and the cohort this gate
    /// protects — exchange deposit addresses — are funded, high-availability
    /// accounts that resolve on the happy path.
    func validateRippleRequireDest() async -> Bool {
        guard coin.chain == .ripple else { return true }

        switch await rippleTag.validateRequireDest(toAddress: toAddress, memo: memo) {
        case .satisfied:
            return true
        case .required:
            setGeneralError(message: "destinationTagRequiredError")
            return false
        case .unverified:
            return false
        }
    }

    /// For ERC20-style non-native sends, gas is paid in the chain's native
    /// sibling. Reject if the vault doesn't hold enough of it.
    func validateERC20GasBalance() -> Bool {
        guard !coin.isNativeToken,
              let nativeToken = vault.coins.nativeCoin(chain: coin.chain) else {
            return true
        }
        let nativeBalance = nativeToken.balanceRaw
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
        // Address resolution runs BEFORE the XRP tag/memo rule: it hosts the
        // X-address normalization seam, which can autofill the tag field —
        // validating the tag first would let an autofilled value (e.g. an
        // embedded tag 0) skip validation on prefill paths that never went
        // through the screen's format check.
        guard await validateAddressResolved() else { return false }
        guard validateNotSelfSend() else { return false }
        guard validateRippleTagAndMemo() else { return false }
        guard await validateRippleRequireDest() else { return false }
        guard validateBalance() else { return false }
        return await validateAmountConstraints()
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
        // XRP: keep only a genuine TEXT memo (the tag+memo combo, or a
        // memo-only send). A numeric memo was either consumed as the tag
        // (legacy "type the tag into the memo" workaround) or echoes the tag
        // field, so it must NOT also ride as an on-chain memo — blank it so the
        // tag is the single source of truth and Verify shows one honest row.
        let resolvedTag = resolvedDestinationTag
        let effectiveMemo: String = {
            guard coin.chain == .ripple else { return memo }
            return RippleDestinationTag.parseCanonical(memo) != nil ? "" : memo
        }()
        return SendTransaction(
            coin: coin,
            vault: vault,
            fromAddress: fromAddress,
            toAddress: toAddress,
            toAddressLabel: toAddressLabel,
            amount: amount,
            amountInFiat: amountInFiat,
            memo: effectiveMemo,
            destinationTag: resolvedTag,
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
        cancelPendingAmountCommit()
        amountValidationTask?.cancel()
        amountValidationTask = nil
        amountValidation = .valid
        coin = newCoin
        fromAddress = newCoin.address
        toAddress = ""
        toAddressLabel = nil
        lastResolvedAddress = nil
        amount = ""
        amountInFiat = ""
        memo = ""
        rippleTag.reset()
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
